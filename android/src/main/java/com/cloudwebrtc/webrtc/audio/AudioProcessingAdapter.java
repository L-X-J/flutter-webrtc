package com.cloudwebrtc.webrtc.audio;

import org.webrtc.ExternalAudioProcessingFactory;

import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.List;

public class AudioProcessingAdapter implements ExternalAudioProcessingFactory.AudioProcessing {
    public interface ExternalAudioFrameProcessing {
        void initialize(int sampleRateHz, int numChannels);

        void reset(int newRate);

        void process(int numBands, int numFrames, ByteBuffer buffer);
    }

    // 打断机制相关字段
    private volatile boolean shouldDiscardAudio = false;
    private volatile long discardUntilTime = 0;

    public AudioProcessingAdapter() {}
    List<ExternalAudioFrameProcessing> audioProcessors = new ArrayList<>();

    public void addProcessor(ExternalAudioFrameProcessing audioProcessor) {
        synchronized (audioProcessors) {
            audioProcessors.add(audioProcessor);
        }
    }

    public void removeProcessor(ExternalAudioFrameProcessing audioProcessor) {
        synchronized (audioProcessors) {
            audioProcessors.remove(audioProcessor);
        }
    }

    /**
     * 清空音频缓冲区，实现打断效果
     * @param durationMs 丢弃音频的持续时间（毫秒）
     */
    public void clearAudioBuffer(int durationMs) {
        shouldDiscardAudio = true;
        discardUntilTime = System.currentTimeMillis() + durationMs;
    }

    /**
     * 立即恢复音频播放
     */
    public void resumeAudio() {
        shouldDiscardAudio = false;
        discardUntilTime = 0;
    }

    @Override
    public void initialize(int sampleRateHz, int numChannels) {
        synchronized (audioProcessors) {
            for (ExternalAudioFrameProcessing audioProcessor : audioProcessors) {
                audioProcessor.initialize(sampleRateHz, numChannels);
            }
        }
    }

    @Override
    public void reset(int newRate) {
        synchronized (audioProcessors) {
            for (ExternalAudioFrameProcessing audioProcessor : audioProcessors) {
                audioProcessor.reset(newRate);
            }
        }
    }

    @Override
    public void process(int numBands, int numFrames, ByteBuffer buffer) {
        // 打断逻辑：如果需要丢弃音频，则清空 buffer
        if (shouldDiscardAudio) {
            if (System.currentTimeMillis() < discardUntilTime) {
                // 清空 buffer（静音）
                int position = buffer.position();
                int limit = buffer.limit();
                for (int i = position; i < limit; i++) {
                    buffer.put(i, (byte) 0);
                }
                return; // 跳过后续处理
            } else {
                // 时间到了，恢复正常
                shouldDiscardAudio = false;
            }
        }

        synchronized (audioProcessors) {
            for (ExternalAudioFrameProcessing audioProcessor : audioProcessors) {
                audioProcessor.process(numBands, numFrames, buffer);
            }
        }
    }
}
