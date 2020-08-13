//
//  BellAVPlayerTracker.m
//  NewRelicVideo
//
//  Created by Andreu Santaren on 05/08/2020.
//  Copyright © 2020 New Relic Inc. All rights reserved.
//

#import "BellAVPlayerTracker.h"

#define TRACKER_TIME_EVENT 1.5

@import AVKit;

@interface BellAVPlayerTracker ()

// AVPlayer weak references
@property (nonatomic, weak) AVPlayer *player;
@property (nonatomic, weak) AVPlayerViewController *playerViewController;

@property (nonatomic) id timeObserver;

@property (nonatomic) BOOL didRequest;
@property (nonatomic) BOOL didStart;
@property (nonatomic) BOOL didEnd;
@property (nonatomic) BOOL isPaused;
@property (nonatomic) BOOL isSeeking;
@property (nonatomic) BOOL isBuffering;
@property (nonatomic) BOOL isLive;

@property (nonatomic) float lastRenditionHeight;
@property (nonatomic) float lastRenditionWidth;
@property (nonatomic) Float64 lastTrackerTimeEvent;

@end

@implementation BellAVPlayerTracker

- (instancetype)initWithAVPlayer:(AVPlayer *)player {
    if (self = [super init]) {
        self.player = player;
    }
    return self;
}

- (instancetype)initWithAVPlayerViewController:(AVPlayerViewController *)playerViewController {
    if (self = [self initWithAVPlayer:playerViewController.player]) {
        self.playerViewController = playerViewController;
    }
    return self;
}

- (void)reset {
    [super reset];
    
    NSLog(@"Tracker Reset");
    
    // Unregister observers
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemTimeJumpedNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemDidPlayToEndTimeNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:nil];
    
    @try {
        [self.player removeObserver:self forKeyPath:@"status"];
    }
    @catch (id e) {}
    
    @try {
        [self.player removeObserver:self forKeyPath:@"rate"];
    }
    @catch (id e) {}
    
    @try {
        [self.player removeObserver:self forKeyPath:@"currentItem.status"];
    }
    @catch (id e) {}
    
    @try {
        [self.player removeObserver:self forKeyPath:@"currentItem.playbackBufferEmpty"];
    }
    @catch (id e) {}
    
    @try {
        [self.player removeObserver:self forKeyPath:@"currentItem.playbackBufferFull"];
    }
    @catch (id e) {}
    
    @try {
        [self.player removeObserver:self forKeyPath:@"currentItem.playbackLikelyToKeepUp"];
    }
    @catch (id e) {}
    
    @try {
        [self.player removeObserver:self forKeyPath:@"timeControlStatus"];
    }
    @catch (id e) {}
    
    @try {
        [self.player removeObserver:self forKeyPath:@"reasonForWaitingToPlay"];
    }
    @catch (id e) {}
    
    @try {
        [self.player removeObserver:self forKeyPath:@"currentItem"];
    }
    @catch (id e) {}
    
    @try {
        [self.player removeTimeObserver:self.timeObserver];
    }
    @catch(id e) {}
    
    self.didRequest = NO;
    self.didStart = NO;
    self.didEnd = NO;
    self.isPaused = NO;
    self.isSeeking = NO;
    self.isBuffering = NO;
    self.isLive = NO;
    
    self.lastRenditionHeight = 0;
    self.lastRenditionWidth = 0;
    self.lastTrackerTimeEvent = 0;
}

- (void)setup {
    [super setup];
    
    NSLog(@"Tracker Setup");

    // Register observers
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(itemTimeJumpedNotification:)
                                                 name:AVPlayerItemTimeJumpedNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(itemDidPlayToEndTimeNotification:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(itemFailedToPlayToEndTimeNotification:)
                                                 name:AVPlayerItemFailedToPlayToEndTimeNotification
                                               object:nil];

    [self.player addObserver:self
                  forKeyPath:@"status"
                     options:(NSKeyValueObservingOptionNew)
                     context:NULL];
    
    [self.player addObserver:self
                  forKeyPath:@"rate"
                     options:(NSKeyValueObservingOptionNew)
                     context:NULL];
    
    [self.player addObserver:self
                  forKeyPath:@"currentItem.status"
                     options:(NSKeyValueObservingOptionNew)
                     context:NULL];
    
    /*
    [self.player addObserver:self
                  forKeyPath:@"currentItem.loadedTimeRanges"
                     options:NSKeyValueObservingOptionNew
                     context:NULL];
    */
    
    [self.player addObserver:self
                  forKeyPath:@"currentItem.playbackBufferEmpty"
                     options:NSKeyValueObservingOptionNew
                     context:NULL];
    
    [self.player addObserver:self
                  forKeyPath:@"currentItem.playbackBufferFull"
                     options:NSKeyValueObservingOptionNew
                     context:NULL];

    [self.player addObserver:self
                  forKeyPath:@"currentItem.playbackLikelyToKeepUp"
                     options:NSKeyValueObservingOptionNew
                     context:NULL];
    
    [self.player addObserver:self
                  forKeyPath:@"timeControlStatus"
                     options:NSKeyValueObservingOptionNew
                     context:NULL];
    
    [self.player addObserver:self
                  forKeyPath:@"reasonForWaitingToPlay"
                     options:NSKeyValueObservingOptionNew
                     context:NULL];
    
    [self.player addObserver:self
                  forKeyPath:@"currentItem"
                     options:NSKeyValueObservingOptionNew
                     context:NULL];
    
    self.timeObserver =
    [self.player addPeriodicTimeObserverForInterval:CMTimeMake(1, 2) queue:NULL usingBlock:^(CMTime time) {
        
        NSLog(@"(BellAVPlayerTracker) Time Observer = %f , rate = %f , duration = %f", CMTimeGetSeconds(time), self.player.rate, CMTimeGetSeconds(self.player.currentItem.duration));
        
        // Check various state changes periodically
        [self periodicVideoStateCheck];
        
        // If duration is NaN, then is live streaming. Otherwise is VoD.
        self.isLive = isnan(CMTimeGetSeconds(self.player.currentItem.duration));
        
        if (self.player.rate == 1.0) {
            [self goStart];
            [self goBufferEnd];
            [self goResume];
        }
        else if (self.player.rate == 0.0) {
            if ([self readyToEnd]) {
                [self goEnd];
            }
            else {
                [self goPause];
            }
        }
    }];
    
    [self sendPlayerReady];
}

// KVO observer method
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSString *,id> *)change
                       context:(void *)context {
    
    NSLog(@"(BellAVPlayerTracker) Observed keyPath = %@ , object = %@ , change = %@ , context = %@", keyPath, object, change, context);
    
    if ([keyPath isEqualToString:@"currentItem.playbackBufferEmpty"]) {
        if (!self.isBuffering && self.isPaused && self.player.rate == 0.0) {
            [self goSeekStart];
        }
        //[self goBufferStart];
    }
    else if ([keyPath isEqualToString:@"currentItem.playbackLikelyToKeepUp"]) {
        [self goRequest];
        //[self goBufferEnd];
    }
    else if ([keyPath isEqualToString:@"status"]) {
        if (self.player.currentItem.status == AVPlayerItemStatusFailed) {
            NSLog(@"(BellAVPlayerTracker) Error While Playing = %@", self.player.currentItem.error);
            
            if (self.player.currentItem.error) {
                [self sendError:self.player.currentItem.error];
            }
            else {
                [self sendError:nil];
            }
        }
    }
    else if ([keyPath isEqualToString:@"currentItem"]) {
        if (self.player.currentItem != nil) {
            NSLog(@"(BellAVPlayerTracker) New Video Session!");
            [self goNext];
        }
    }
    else if ([keyPath isEqualToString:@"timeControlStatus"]) {
        if (self.player.timeControlStatus == AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate) {
            [self goBufferStart];
        }
        else {
            [self goBufferEnd];
        }
    }
}

- (void)itemTimeJumpedNotification:(NSNotification *)notification {
    NSLog(@"(BellAVPlayerTracker) Time Jumped! = %f", CMTimeGetSeconds(self.player.currentItem.currentTime));
}

- (void)itemDidPlayToEndTimeNotification:(NSNotification *)notification {
    NSLog(@"(BellAVPlayerTracker) Did Play To End");
    if ([self readyToEnd]) {
        [self goEnd];
    }
}

- (void)itemFailedToPlayToEndTimeNotification:(NSNotification *)notification {
    NSError *error = notification.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey];
    [self sendError:error];
}

- (BOOL)readyToEnd {
    if (CMTimeGetSeconds(self.player.currentItem.currentTime) > CMTimeGetSeconds(self.player.currentItem.duration) - 0.6) {
        return YES;
    }
    else {
        return NO;
    }
}

- (void)periodicVideoStateCheck {
    if (self.lastTrackerTimeEvent == 0) {
        self.lastTrackerTimeEvent = CMTimeGetSeconds(self.player.currentItem.currentTime);
        [self checkRenditionChange];
    }
    else {
        if (CMTimeGetSeconds(self.player.currentItem.currentTime) - self.lastTrackerTimeEvent > TRACKER_TIME_EVENT) {
            self.lastTrackerTimeEvent = CMTimeGetSeconds(self.player.currentItem.currentTime);
            [self checkRenditionChange];
        }
    }
}

- (void)checkRenditionChange {
    if (self.lastRenditionWidth == 0 || self.lastRenditionHeight == 0) {
        self.lastRenditionHeight = [self getRenditionHeight].floatValue;
        self.lastRenditionWidth = [self getRenditionWidth].floatValue;
    }
    else {
        float currentRenditionHeight =  [self getRenditionHeight].floatValue;
        float currentRenditionWidth =  [self getRenditionWidth].floatValue;
        float currentMul = currentRenditionWidth * currentRenditionHeight;
        float lastMul = self.lastRenditionWidth * self.lastRenditionHeight;
        
        if (currentMul != lastMul) {
            NSLog(@"(BellAVPlayerTracker) RESOLUTION CHANGED, H = %f, W = %f", currentRenditionHeight, currentRenditionWidth);
            
            if (currentMul > lastMul) {
                [self setOptionKey:@"shift" value:@"up" forAction:CONTENT_RENDITION_CHANGE];
            }
            else {
                [self setOptionKey:@"shift" value:@"down" forAction:CONTENT_RENDITION_CHANGE];
            }
            
            [self sendRenditionChange];
            
            self.lastRenditionHeight = currentRenditionHeight;
            self.lastRenditionWidth = currentRenditionWidth;
        }
    }
}

#pragma mark - Events senders

- (BOOL)goNext {
    NSLog(@"(BellAVPlayerTracker) goNext");
    
    if (self.didRequest) {
        [self goEnd];
        self.didRequest = NO;
        return YES;
    }
    else {
        return NO;
    }
}

- (BOOL)goRequest {
    NSLog(@"(BellAVPlayerTracker) goRequest");
    
    if (!self.didRequest) {
        [self sendRequest];
        self.didRequest = YES;
        self.didStart = NO;
        self.didEnd = NO;
        self.isPaused = NO;
        self.isSeeking = NO;
        self.isBuffering = NO;
        self.isLive = NO;
        return YES;
    }
    else {
        return NO;
    }
}

- (BOOL)goStart {
    NSLog(@"(BellAVPlayerTracker) goStart");
    
    if (self.didRequest && !self.didStart) {
        [self sendStart];
        self.didStart = YES;
        return YES;
    }
    else {
        return NO;
    }
}

- (BOOL)goPause {
    NSLog(@"(BellAVPlayerTracker) goPause");
    
    if (self.didEnd) return NO;
    
    if (self.didStart && !self.isPaused) {
        [self sendPause];
        self.isPaused = YES;
        return YES;
    }
    else {
        return NO;
    }
}

- (BOOL)goResume {
    NSLog(@"(BellAVPlayerTracker) goResume");
    
    if (self.didEnd) return NO;
    
    if (self.isPaused) {
        [self goSeekEnd];
        [self sendResume];
        self.isPaused = NO;
        return YES;
    }
    else {
        return NO;
    }
}

- (BOOL)goBufferStart {
    NSLog(@"(BellAVPlayerTracker) goBufferStart");
    
    if (self.didEnd) return NO;
    
    if (!self.isBuffering) {
        [self sendBufferStart];
        self.isBuffering = YES;
        return YES;
    }
    else {
        return NO;
    }
}

- (BOOL)goBufferEnd {
    NSLog(@"(BellAVPlayerTracker) goBufferEnd");
    
    if (self.didEnd) return NO;
    
    if (self.isBuffering) {
        [self sendBufferEnd];
        self.isBuffering = NO;
        return YES;
    }
    else {
        return NO;
    }
}

- (BOOL)goSeekStart {
    NSLog(@"(BellAVPlayerTracker) goSeekStart");
    
    if (self.didEnd) return NO;
    
    if (!self.isSeeking) {
        [self sendSeekStart];
        self.isSeeking = YES;
        return YES;
    }
    else {
        return NO;
    }
}

- (BOOL)goSeekEnd {
    NSLog(@"(BellAVPlayerTracker) goSeekEnd");
    
    if (self.didEnd) return NO;
    
    if (self.isSeeking) {
        [self sendSeekEnd];
        self.isSeeking = NO;
        return YES;
    }
    else {
        return NO;
    }
}

- (BOOL)goEnd {
    NSLog(@"(BellAVPlayerTracker) goEnd");
    
    if (!self.didEnd) {
        [self sendEnd];
        return YES;
    }
    else {
        return NO;
    }
}

#pragma mark - ContentsTracker getters

- (NSString *)getTrackerName {
    return @"belltracker";
}

- (NSString *)getTrackerVersion {
    return @"0.11.0";
}

- (NSString *)getPlayerVersion {
    return [[UIDevice currentDevice] systemVersion];
}

- (NSString *)getPlayerName {
    return @"avplayer";
}

- (NSNumber *)getBitrate {
    AVPlayerItemAccessLogEvent *event = [self.player.currentItem.accessLog.events lastObject];
    return @(event.indicatedBitrate);
}

- (NSNumber *)getRenditionWidth {
    return @(self.player.currentItem.presentationSize.width);
}

- (NSNumber *)getRenditionHeight {
    return @(self.player.currentItem.presentationSize.height);
}

- (NSNumber *)getDuration {
    Float64 duration = CMTimeGetSeconds(self.player.currentItem.duration);
    if (isnan(duration)) {
        return @0;
    }
    else {
        return @(duration * 1000.0f);
    }
}

- (NSNumber *)getPlayhead {
    Float64 pos = CMTimeGetSeconds(self.player.currentItem.currentTime);
    if (isnan(pos)) {
        return @0;
    }
    else {
        return @(pos * 1000.0f);
    }
}

- (NSString *)getSrc {
    AVAsset *currentPlayerAsset = self.player.currentItem.asset;
    if (![currentPlayerAsset isKindOfClass:AVURLAsset.class]) return @"";
    return [[(AVURLAsset *)currentPlayerAsset URL] absoluteString];
}

- (NSNumber *)getPlayrate {
    return @(self.player.rate);
}

- (NSNumber *)getFps {
    AVAsset *asset = self.player.currentItem.asset;
    if (asset) {
        NSError *error;
        AVKeyValueStatus kvostatus = [asset statusOfValueForKey:@"tracks" error:&error];

        if (kvostatus != AVKeyValueStatusLoaded) {
            return nil;
        }
        
        AVAssetTrack *videoATrack = [[asset tracksWithMediaType:AVMediaTypeVideo] lastObject];
        if (videoATrack) {
            return @(videoATrack.nominalFrameRate);
        }
    }
    return nil;
}

- (NSNumber *)getIsLive {
    return @(self.isLive);
}

- (NSNumber *)getIsMuted {
    return @(self.player.muted);
}

#pragma mark - Overwrite senders

- (void)sendEnd {
    [self goBufferEnd];
    [self goSeekEnd];
    [self goResume];
    
    [super sendEnd];
    NSLog(@"(BellAVPlayerTracker) sendEnd");
    self.didEnd = YES;
}

- (void)sendSeekStart {
    [super sendSeekStart];
    self.isSeeking = YES;
}

- (void)sendSeekEnd {
    [super sendSeekEnd];
    self.isSeeking = NO;
}

@end
