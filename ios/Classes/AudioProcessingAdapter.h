#import <Foundation/Foundation.h>
#import <WebRTC/WebRTC.h>

@protocol ExternalAudioProcessingDelegate

- (void)audioProcessingInitializeWithSampleRate:(size_t)sampleRateHz channels:(size_t)channels;

- (void)audioProcessingProcess:(RTC_OBJC_TYPE(RTCAudioBuffer) * _Nonnull)audioBuffer;

- (void)audioProcessingRelease;

@end

@interface AudioProcessingAdapter : NSObject <RTCAudioCustomProcessingDelegate>

// 打断机制属性
@property (nonatomic, assign) BOOL shouldDiscardAudio;
@property (nonatomic, assign) NSTimeInterval discardUntilTime;

- (nonnull instancetype)init;

- (void)addProcessing:(id<ExternalAudioProcessingDelegate> _Nonnull)processor;

- (void)removeProcessing:(id<ExternalAudioProcessingDelegate> _Nonnull)processor;

- (void)addAudioRenderer:(nonnull id<RTCAudioRenderer>)renderer;

- (void)removeAudioRenderer:(nonnull id<RTCAudioRenderer>)renderer;

// 打断方法
- (void)clearAudioBufferWithDuration:(NSTimeInterval)durationMs;
- (void)resumeAudio;

@end
