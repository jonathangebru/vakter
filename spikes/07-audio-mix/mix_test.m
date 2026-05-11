#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

// Spike 7 — Verify simultaneous AVAudioEngine sine tone + AVSpeechSynthesizer voice cue.
//
// What this test does:
//  1. Boot AVAudioEngine, connect an AVAudioSourceNode that emits a sine tone.
//  2. Start AVSpeechSynthesizer speaking the planned voice cue.
//  3. Both should be audible simultaneously for ~3 seconds.
//  4. Stop both cleanly.
//
// What we want to learn:
//  - Does the synthesizer actually emit audio in a CLI-context binary?
//  - Does it conflict with AVAudioEngine on the same output device?
//  - Is the mixed output coherent (no dropouts, glitches, or silent overlay)?

@interface SpeechWaiter : NSObject <AVSpeechSynthesizerDelegate>
@property (nonatomic) BOOL didFinish;
@end

@implementation SpeechWaiter
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didFinishSpeechUtterance:(AVSpeechUtterance *)utterance {
    self.didFinish = YES;
    NSLog(@"  delegate: speech finished");
}
- (void)speechSynthesizer:(AVSpeechSynthesizer *)synthesizer didStartSpeechUtterance:(AVSpeechUtterance *)utterance {
    NSLog(@"  delegate: speech started");
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        printf("== Spike 7: AVSpeechSynthesizer + tone mixing ==\n\n");

        // -- Tone setup via AVAudioEngine -------------------------------------
        AVAudioEngine *engine = [[AVAudioEngine alloc] init];
        AVAudioFormat *fmt = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:2];
        if (!fmt) { printf("FAIL: could not build audio format\n"); return 1; }

        __block double phase = 0.0;
        const double freq = 880.0;
        const double sr = fmt.sampleRate;
        const double twoPi = 2.0 * M_PI;

        AVAudioSourceNode *src = [[AVAudioSourceNode alloc] initWithFormat:fmt renderBlock:^OSStatus(BOOL *isSilence, const AudioTimeStamp *ts, AVAudioFrameCount frameCount, AudioBufferList *outputData) {
            for (UInt32 b = 0; b < outputData->mNumberBuffers; b++) {
                float *out = (float *)outputData->mBuffers[b].mData;
                double localPhase = phase;
                for (AVAudioFrameCount i = 0; i < frameCount; i++) {
                    out[i] = 0.10f * (float)sin(localPhase); // -20 dBFS gentle
                    localPhase += twoPi * freq / sr;
                    if (localPhase > twoPi) localPhase -= twoPi;
                }
                if (b == outputData->mNumberBuffers - 1) phase = localPhase;
            }
            *isSilence = NO;
            return noErr;
        }];

        [engine attachNode:src];
        [engine connect:src to:engine.mainMixerNode format:fmt];

        NSError *err = nil;
        if (![engine startAndReturnError:&err]) {
            printf("FAIL: engine start: %s\n", err.localizedDescription.UTF8String);
            return 1;
        }
        printf("✅ AVAudioEngine started; sine tone at 880 Hz playing.\n");

        // -- Voice cue via AVSpeechSynthesizer -------------------------------
        AVSpeechSynthesizer *synth = [[AVSpeechSynthesizer alloc] init];
        SpeechWaiter *waiter = [[SpeechWaiter alloc] init];
        synth.delegate = waiter;

        AVSpeechUtterance *utt = [AVSpeechUtterance speechUtteranceWithString:
            @"This MacBook is being tracked. Please put it down."];
        utt.voice = [AVSpeechSynthesisVoice voiceWithLanguage:@"en-US"];
        utt.rate = AVSpeechUtteranceDefaultSpeechRate;
        utt.volume = 1.0;
        utt.pitchMultiplier = 1.0;

        printf("Speaking voice cue while tone continues...\n");
        [synth speakUtterance:utt];

        // Wait up to ~5 seconds for speech to finish OR timeout
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
        while (!waiter.didFinish && [deadline timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }

        // Hold tone briefly so the user can hear no glitches after speech ends.
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];

        [engine stop];
        printf("Engine stopped.\n\n");

        printf("== Result ==\n");
        if (waiter.didFinish) {
            printf("✅ Speech utterance completed normally alongside the tone.\n");
            printf("→ AVSpeechSynthesizer can run concurrently with AVAudioEngine.\n");
            printf("→ Mixed playback strategy is viable.\n");
        } else {
            printf("⚠ Speech did not finish within 5s — investigate route/output conflicts.\n");
        }
    }
    return 0;
}
