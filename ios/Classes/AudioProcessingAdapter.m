#import "AudioProcessingAdapter.h"
#import <WebRTC/RTCAudioRenderer.h>
#import <os/lock.h>

@implementation AudioProcessingAdapter {
  NSMutableArray<id<RTCAudioRenderer>>* _renderers;
  NSMutableArray<id<ExternalAudioProcessingDelegate>>* _processors;
  os_unfair_lock _lock;
}

@synthesize shouldDiscardAudio = _shouldDiscardAudio;
@synthesize discardUntilTime = _discardUntilTime;

- (instancetype)init {
  self = [super init];
  if (self) {
    _lock = OS_UNFAIR_LOCK_INIT;
    _renderers = [[NSMutableArray<id<RTCAudioRenderer>> alloc] init];
    _processors = [[NSMutableArray<id<ExternalAudioProcessingDelegate>> alloc] init];
    _shouldDiscardAudio = NO;
    _discardUntilTime = 0;
  }
  return self;
}

- (void)addProcessing:(id<ExternalAudioProcessingDelegate> _Nonnull)processor {
  os_unfair_lock_lock(&_lock);
  [_processors addObject:processor];
  os_unfair_lock_unlock(&_lock);
}

- (void)removeProcessing:(id<ExternalAudioProcessingDelegate> _Nonnull)processor {
  os_unfair_lock_lock(&_lock);
  _processors = [[_processors
      filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject,
                                                                        NSDictionary* bindings) {
        return evaluatedObject != processor;
      }]] mutableCopy];
  os_unfair_lock_unlock(&_lock);
}

- (void)addAudioRenderer:(nonnull id<RTCAudioRenderer>)renderer {
  os_unfair_lock_lock(&_lock);
  [_renderers addObject:renderer];
  os_unfair_lock_unlock(&_lock);
}

- (void)removeAudioRenderer:(nonnull id<RTCAudioRenderer>)renderer {
  os_unfair_lock_lock(&_lock);
  _renderers = [[_renderers
      filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject,
                                                                        NSDictionary* bindings) {
        return evaluatedObject != renderer;
      }]] mutableCopy];
  os_unfair_lock_unlock(&_lock);
}

- (void)clearAudioBufferWithDuration:(NSTimeInterval)durationMs {
  _shouldDiscardAudio = YES;
  _discardUntilTime = [[NSDate date] timeIntervalSince1970] * 1000.0 + durationMs;
  NSLog(@"[AudioProcessingAdapter] clearAudioBuffer for %f ms", durationMs);
}

- (void)resumeAudio {
  _shouldDiscardAudio = NO;
  _discardUntilTime = 0;
  NSLog(@"[AudioProcessingAdapter] resumeAudio");
}

- (void)audioProcessingInitializeWithSampleRate:(size_t)sampleRateHz channels:(size_t)channels {
  os_unfair_lock_lock(&_lock);
  for (id<ExternalAudioProcessingDelegate> processor in _processors) {
    [processor audioProcessingInitializeWithSampleRate:sampleRateHz channels:channels];
  }
  os_unfair_lock_unlock(&_lock);
}

- (AVAudioPCMBuffer*)toPCMBuffer:(RTC_OBJC_TYPE(RTCAudioBuffer) *)audioBuffer {
  AVAudioFormat* format =
      [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16
                                       sampleRate:audioBuffer.frames * 100.0
                                         channels:(AVAudioChannelCount)audioBuffer.channels
                                      interleaved:NO];
  AVAudioPCMBuffer* pcmBuffer =
      [[AVAudioPCMBuffer alloc] initWithPCMFormat:format
                                    frameCapacity:(AVAudioFrameCount)audioBuffer.frames];
  if (!pcmBuffer) {
    NSLog(@"Failed to create AVAudioPCMBuffer");
    return nil;
  }
  pcmBuffer.frameLength = (AVAudioFrameCount)audioBuffer.frames;
  for (int i = 0; i < audioBuffer.channels; i++) {
    float* sourceBuffer = [audioBuffer rawBufferForChannel:i];
    int16_t* targetBuffer = (int16_t*)pcmBuffer.int16ChannelData[i];
    for (int frame = 0; frame < audioBuffer.frames; frame++) {
      targetBuffer[frame] = sourceBuffer[frame];
    }
  }
  return pcmBuffer;
}

- (void)audioProcessingProcess:(RTC_OBJC_TYPE(RTCAudioBuffer) *)audioBuffer {
  // 打断逻辑：如果需要丢弃音频，则清空 buffer
  if (_shouldDiscardAudio) {
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970] * 1000.0;
    if (currentTime < _discardUntilTime) {
      // 清空 buffer（静音）
      for (int i = 0; i < audioBuffer.channels; i++) {
        float* buffer = [audioBuffer rawBufferForChannel:i];
        memset(buffer, 0, audioBuffer.frames * sizeof(float));
      }
      return; // 跳过后续处理
    } else {
      // 时间到了，恢复正常
      _shouldDiscardAudio = NO;
    }
  }

  os_unfair_lock_lock(&_lock);
  for (id<ExternalAudioProcessingDelegate> processor in _processors) {
    [processor audioProcessingProcess:audioBuffer];
  }

  for (id<RTCAudioRenderer> renderer in _renderers) {
    [renderer renderPCMBuffer:[self toPCMBuffer:audioBuffer]];
  }
  os_unfair_lock_unlock(&_lock);
}

- (void)audioProcessingRelease {
  os_unfair_lock_lock(&_lock);
  for (id<ExternalAudioProcessingDelegate> processor in _processors) {
    [processor audioProcessingRelease];
  }
  os_unfair_lock_unlock(&_lock);
}

@end
