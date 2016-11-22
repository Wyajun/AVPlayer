//
//  MmiaVideoPlayView.m
//  MMIA
//
//  Created by wyl on 16/8/14.
//  Copyright © 2016年 MMIA. All rights reserved.
//

#import "MmiaVideoPlayView.h"
#import <TencentOpenAPI/TencentOAuth.h>
#import "AFNetworking.h"
#import "SVProgressHUD+MmiaCustom.h"
#import <MediaPlayer/MediaPlayer.h>

typedef enum : NSUInteger {
    MmiaPlayerNetStateUnknow = -1,
    MmiaPlayerNetStateNotReachable = 0,
    MmiaPlayerNetStateViaWWAN = 1,
    MmiaPlayerNetStateViaWiFi = 2,
} MmiaPlayerNetState;

typedef NS_ENUM(NSInteger, PanDirection){
    PanDirectionHorizontalMoved, // 横向移动
    PanDirectionVerticalMoved    // 纵向移动
};

static void *PlayViewCMTimeValue = &PlayViewCMTimeValue;

static void *PlayViewStatusObservationContext = &PlayViewStatusObservationContext;

#define ShareView_Width 320
#define UpdateProgress_Moment 1.0

@interface MmiaVideoPlayView (){

    UITapGestureRecognizer* singleTap;
    UIView * _shareBtnContainer;
    
    //此时视频是否已经播放结束
    BOOL _isVideoEnd;
    
    //此时视频是否正在播放
    BOOL _isPlaying;
}

@property (nonatomic, strong) AVPlayerItem *playerItem;
/* 播放器 */
@property (nonatomic, strong) AVPlayer *player;

// 播放器的Layer
@property (strong, nonatomic) AVPlayerLayer *playerLayer;


@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIView *topStatusBar;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UIButton * backButton;
@property (nonatomic, strong) UILabel * titleLabel;



@property (nonatomic, strong) UIButton *playOrPauseButton;
@property (nonatomic, strong) UIButton *pauseButton;
@property (nonatomic, strong) UIButton *fullScreenButton;
@property (nonatomic, strong) UISlider *cacheSlider;
@property (nonatomic, strong) UILabel *currentVideoTime;
@property (nonatomic, strong) UILabel *totalVideoTime;

@property (nonatomic, assign) BOOL isBarShowing;
@property (nonatomic, strong) UIActivityIndicatorView *progressView;
/* 定时器 */
@property (nonatomic, strong) NSTimer *progressTimer;

/**
 *  定时器
 */
@property (nonatomic, retain) NSTimer  *autoDismissTimer;

//点击分享的时候从右向左推出来的界面
@property (nonatomic, strong) UIView * shareView;

//网络状态
@property (nonatomic, assign) MmiaPlayerNetState netState;

//声音引导层
@property (nonatomic, strong) UIView * voiceGuideView;
@property (nonatomic, retain) NSTimer *voiceDismissTimer;
@property (nonatomic, assign) PanDirection           panDirection;
@property (nonatomic, strong) UISlider               *volumeViewSlider;


@end

@implementation MmiaVideoPlayView

- (instancetype)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.isVideoPause = NO;
        _isVideoEnd = NO;
        _isPlaying = NO;

        [self initialize];
    }
    return self;
}

- (void)dealloc {
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.playerItem removeObserver:self forKeyPath:@"status"];
    [self.playerItem removeObserver:self forKeyPath:@"playbackBufferEmpty"];
    [self.playerItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp"];
    
    [self.player.currentItem cancelPendingSeeks];
    [self.player.currentItem.asset cancelLoading];
    [self.player pause];
    [self.playerLayer removeFromSuperlayer];
    [self.player replaceCurrentItemWithPlayerItem:nil];
    self.player = nil;
    NSLog(@"VideoPlayView dealloc");
    
}


- (void)layoutSubviews
{
    [super layoutSubviews];
    
    self.playerLayer.frame = self.bounds;
}
#pragma mark - public
//暂停
- (void) pause {
    
    if (!_isPlaying) {
        return;
    }
    self.isVideoPause = YES;
    [self.playOrPauseButton setImage:[UIImage imageNamed:@"videoDetail_play"] forState:UIControlStateNormal];
//    NSLog(@"暂停 Ani");
    [self.progressView stopAnimating];
    [self.player pause];
    [self removeProgressTimer];

}
//播放
- (void) play {
    
    if (_isPlaying) {
        return;
    }
    
    [self.playOrPauseButton setImage:[UIImage imageNamed:@"videoDetail_pause"] forState:UIControlStateNormal];
    self.isVideoPause = NO;
    if (!_isVideoEnd) {
        [self.player play];
        [self addProgressTimer];
    }else{
        
        WeakSelf(wself);
        if (self.progressSlider.value == 1.0) {
            self.progressSlider.value = 0.0;
            NSTimeInterval currentTime = CMTimeGetSeconds(self.player.currentItem.duration) * self.progressSlider.value ;
            [self.player seekToTime:CMTimeMakeWithSeconds(currentTime, NSEC_PER_SEC) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
                _isVideoEnd = NO;
                [wself.player play];
                [wself addProgressTimer];
            }];

        }else{
            _isVideoEnd = NO;
            [self.player play];
            [self addProgressTimer];

        }
    }


}

//网络情况差的时候显示所有的工具栏
- (void) showAllToolBar {
    
    self.isVideoPause = YES;
    [self.playOrPauseButton setImage:[UIImage imageNamed:@"videoDetail_play"] forState:UIControlStateNormal];
    [self.progressView stopAnimating];
    [self.player pause];
    [self removeProgressTimer];
    
    self.bottomBar.alpha = 1.0;
    self.playOrPauseButton.alpha = 1.0;
    self.topBar.alpha = 1.0;
    self.backButton.alpha = 1.0;
}

#pragma mark - Button Response
- (void) playOrPauseButtonClick: (UIButton *) playOrPauseButton {
    
    if (_videoUrl.length) {
        if (self.isVideoPause) {
            [self play];
        }else {
            [self pause];
        }

    }else{
        if (self.delegate) {
            [self.delegate MmiaVideoPlayerControlViewPlayButtonClickWhenNetworkNormal];
        }
    }
   
}

#pragma mark - Notification Action
- (void)moviePlayDidEnd:(NSNotification *)notification {
    
    [self updateTime];
    self.progressSlider.value = 1;
    self.isVideoPause = YES;
    _isVideoEnd = YES;
    [self removeProgressTimer];
    
    [self.player pause];
    self.bottomBar.alpha = 1.0;
    self.playOrPauseButton.alpha = 1.0;
    self.topBar.alpha = 1.0;
    self.backButton.alpha = 1.0;
    
    [self.playOrPauseButton setImage:[UIImage imageNamed:@"videoDetail_play"] forState:UIControlStateNormal];
    
    if (self.delegate) {
        [self.delegate MmiaVideoPlayerControlViewFinishPlay];
    }
}

#pragma mark - Gesterture
- (void)progressSliderTouchUpInside {

    [self pause];
    [self.progressView startAnimating];
    NSTimeInterval currentTime = CMTimeGetSeconds(self.player.currentItem.duration) * self.progressSlider.value;
    __weak typeof (self) wself = self;
    // 设置当前播放时间
    [self.player seekToTime:CMTimeMakeWithSeconds(currentTime, NSEC_PER_SEC) toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
        if (!wself.isVideoPause) {
            [wself addProgressTimer];
            [wself.player play];
//            NSLog(@"抬手 ani");
            [wself.progressView stopAnimating];
        }else{
            _isPlaying = NO;
        }
    }];

}
- (void)progressSliderTouchDown {

//    NSLog(@"sliderTouchDown");
    if (self.progressTimer) {
        [self removeProgressTimer];
    }

}

- (void)progressSliderValueChanged {

//    NSLog(@"sliderValueChange");
    if (self.progressTimer) {
        [self removeProgressTimer];
    }
    NSTimeInterval currentTime = CMTimeGetSeconds(self.player.currentItem.duration) * self.progressSlider.value;
    NSTimeInterval duration = CMTimeGetSeconds(self.player.currentItem.duration);
    [self updateTimeWithCurrentTime:currentTime duration:duration];

}


- (void)handleSingleTap:(UITapGestureRecognizer *)sender{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(autoDismissBottomView:) object:nil];

    WeakSelf(wself);
    [self.autoDismissTimer invalidate];
    self.autoDismissTimer = nil;
    self.autoDismissTimer = [NSTimer timerWithTimeInterval:8.0 target:self selector:@selector(autoDismissBottomView:) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:self.autoDismissTimer forMode:NSDefaultRunLoopMode];
    [UIView animateWithDuration:0.5 animations:^{
        if (wself.bottomBar.alpha == 0.0) {
            wself.bottomBar.alpha = 1.0;
            wself.playOrPauseButton.alpha = 1.0;
            wself.topBar.alpha = 1.0;
            wself.backButton.alpha = 1.0;
            
            [UIApplication sharedApplication].statusBarHidden = NO;
        }else{
            wself.bottomBar.alpha = 0.0;
            wself.topBar.alpha = 0.0;
            wself.playOrPauseButton.alpha = 0.0;
            if (!_isPortrait) {
                wself.backButton.alpha = 0.0;
                [UIApplication sharedApplication].statusBarHidden = YES;
            }
        }
    } completion:^(BOOL finish){
        
    }];
}

- (void) voiceGuideViewTap: (UITapGestureRecognizer *) tapGes {
    WeakSelf(wself);
    [self.voiceDismissTimer invalidate];
    self.voiceDismissTimer = nil;
    [UIView animateWithDuration:0.5 animations:^{
        wself.voiceGuideView.alpha = 0.0;
    } completion:^(BOOL finish){
        [wself.voiceGuideView removeFromSuperview];
    }];

}

- (void)voiceControlGesture:(UIPanGestureRecognizer *)pan
{
    // 我们要响应水平移动和垂直移动
    // 根据上次和本次移动的位置，算出一个速率的point
    CGPoint veloctyPoint = [pan velocityInView:self];
    
    // 判断是垂直移动还是水平移动
    switch (pan.state) {
        case UIGestureRecognizerStateBegan:{ // 开始移动
            // 使用绝对值来判断移动的方向
            CGFloat x = fabs(veloctyPoint.x);
            CGFloat y = fabs(veloctyPoint.y);
            if (x < y){ // 垂直移动
                self.panDirection = PanDirectionVerticalMoved;
            }else{
                self.panDirection = PanDirectionHorizontalMoved;
            }
            break;
        }
        case UIGestureRecognizerStateChanged:{ // 正在移动
            switch (self.panDirection) {
                case PanDirectionVerticalMoved:{
                    self.volumeViewSlider.value -= veloctyPoint.y / 10000;
                    break;
                }
                default:
                    break;
            }
            break;
        }
        case UIGestureRecognizerStateEnded:{ // 移动停止
            break;
        }
        default:
            break;
    }
    
    
}


#pragma mark - Button Response
- (void) MmiaVideoPlayerControlViewBackButtonClick {
    if (self.delegate) {
        [self.delegate MmiaVideoPlayerControlViewBackButtonClick];
    }
}

- (void) fullScreenButtonClick {
    if (self.delegate) {
        [self.delegate MmiaVideoPlayerControlViewFullScreenButtonClick];
    }
}

//总 分享按钮的点击
- (void) shareBtnClick {
    //添加 点击分享
    [self addSubview:self.shareView];
    WeakSelf(wself);
    [UIView animateWithDuration:0.4 animations:^{
        _shareBtnContainer.left = wself.bounds.size.width - ShareView_Width;
    } completion:^(BOOL finished) {
        
    }];
    
}

#pragma mark - private

-(void)autoDismissBottomView:(NSTimer *)timer{
    
    if(self.player.rate==1.0f){
        if (self.bottomBar.alpha==1.0) {
            WeakSelf(wself);
            [UIView animateWithDuration:0.5 animations:^{
                wself.bottomBar.alpha = 0.0;
                wself.topBar.alpha = 0.0;
                wself.playOrPauseButton.alpha = 0.0;
                if (!_isPortrait) {
                    wself.backButton.alpha = 0.0;
                    [UIApplication sharedApplication].statusBarHidden = YES;
                }
            } completion:^(BOOL finish){
                
            }];
        }
    }
    
}

- (void) voiceGuideViewAutoDismiss: (NSTimer *) timer {
    
    WeakSelf(wself);
    [UIView animateWithDuration:0.5 animations:^{
        wself.voiceGuideView.alpha = 0.0;
    } completion:^(BOOL finish){
        [wself.voiceGuideView removeFromSuperview];
    }];
}

/**
 *  获取系统音量
 */
- (void)configureVolume
{
    MPVolumeView *volumeView = [[MPVolumeView alloc] init];
    _volumeViewSlider = nil;
    for (UIView *view in [volumeView subviews]){
        if ([view.class.description isEqualToString:@"MPVolumeSlider"]){
            _volumeViewSlider = (UISlider *)view;
            break;
        }
    }
}

- (void) addVoiceControlGuide {
    BOOL isKnow;
    NSString * keyStr = @"videoDetail_first";
    isKnow = [[NSUserDefaults standardUserDefaults] objectForKey:keyStr];
    if (!isKnow) {
        WeakSelf(wself);
        [self addSubview:self.voiceGuideView];
        [self.voiceGuideView mas_makeConstraints:^(MASConstraintMaker *make) {
            make.edges.equalTo(wself);
        }];
        self.voiceDismissTimer = [NSTimer timerWithTimeInterval:5.0 target:self selector:@selector(voiceGuideViewAutoDismiss:) userInfo:nil repeats:NO];
        [[NSRunLoop currentRunLoop] addTimer:self.voiceDismissTimer forMode:NSDefaultRunLoopMode];
    }
    //添加音量调节
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(voiceControlGesture:)];
    [self addGestureRecognizer:pan];
    [self configureVolume];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:keyStr];

}

#pragma mark - 定时器操作
- (void)addProgressTimer
{
    _isPlaying = YES;
    self.progressTimer = [NSTimer scheduledTimerWithTimeInterval:UpdateProgress_Moment target:self selector:@selector(updateProgressInfo) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.progressTimer forMode:NSRunLoopCommonModes];
}

- (void)removeProgressTimer
{
    _isPlaying = NO;
    [self.progressTimer invalidate];
    self.progressTimer = nil;
}

- (void)updateProgressInfo
{
    // 1.更新时间
    [self updateTime];
    // 2.设置进度条的value
    self.progressSlider.value = CMTimeGetSeconds(self.player.currentTime) / CMTimeGetSeconds(self.player.currentItem.duration);
//    NSLog(@"self.progressSlider.value %f",self.progressSlider.value);
    // 计算缓冲进度
    NSTimeInterval timeInterval = [self availableDuration];
    CMTime duration             = self.playerItem.duration;
    CGFloat totalDuration       = CMTimeGetSeconds(duration);
    self.cacheSlider.value = timeInterval / totalDuration;

}

/**
 *  计算缓冲进度
 *
 *  @return 缓冲进度
 */
- (NSTimeInterval)availableDuration {
    NSArray *loadedTimeRanges = [_playerItem loadedTimeRanges];
    CMTimeRange timeRange     = [loadedTimeRanges.firstObject CMTimeRangeValue];// 获取缓冲区域
    float startSeconds        = CMTimeGetSeconds(timeRange.start);
    float durationSeconds     = CMTimeGetSeconds(timeRange.duration);
    NSTimeInterval result     = startSeconds + durationSeconds;// 计算缓冲总进度
    return result;
}


- (void)updateTime
{
    NSTimeInterval duration = CMTimeGetSeconds(self.player.currentItem.duration);
    NSTimeInterval currentTime = CMTimeGetSeconds(self.player.currentTime);
    
    return [self updateTimeWithCurrentTime:currentTime duration:duration];
}

#pragma mark - 设置播放的视频
-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context {
    
    if ([keyPath isEqualToString:@"status"]) {
        AVPlayerItem *item = (AVPlayerItem *)object;
        if (item.status == AVPlayerItemStatusReadyToPlay) {
//            NSLog(@"readyToPlay ani");
            [self.progressView stopAnimating];
            self.progressSlider.userInteractionEnabled = YES;
        }else{
            self.progressSlider.userInteractionEnabled = NO;
        }
        
    }else if ([keyPath isEqualToString:@"playbackBufferEmpty"]){
        // 当缓冲是空的时候
//        NSLog(@"缓冲为空");
        if (self.netState == MmiaPlayerNetStateNotReachable || self.netState == MmiaPlayerNetStateUnknow) {
            [self.progressView stopAnimating];
            [self showAllToolBar];
            [SVProgressHUD setMinimumDismissTimeInterval:3.0];
            [SVProgressHUD setMmiaProgressHUD];
            [SVProgressHUD showImage:nil status:@"网络连接失败"];
        }else{
            WeakSelf(wself);
            [self.player pause];
            [self.progressView startAnimating];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (!_isVideoPause) {
                    [wself.player play];
                    [wself.progressView stopAnimating];
                }

            });

        }
    }else if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"]){
        // 当缓冲好的时候
//        NSLog(@"缓冲好了");
        [self.progressView stopAnimating];
        if (!self.isVideoPause) {
            [self.player play];
        }
    }
}

- (void)updateTimeWithCurrentTime:(NSTimeInterval)currentTime duration:(NSTimeInterval)duration
{
    
    NSInteger dMin = duration / 60;
    NSInteger dSec = (NSInteger)duration % 60;
    
    NSInteger cMin = currentTime / 60;
    NSInteger cSec = (NSInteger)currentTime % 60;
    
    dMin = dMin<0?0:dMin;
    dSec = dSec<0?0:dSec;
    cMin = cMin<0?0:cMin;
    cSec = cSec<0?0:cSec;
    
    NSString *durationString = [NSString stringWithFormat:@"%02ld:%02ld", (long)dMin, (long)dSec];
    NSString *currentString = [NSString stringWithFormat:@"%02ld:%02ld", (long)cMin, (long)cSec];
    
    self.currentVideoTime.text = currentString;
    self.totalVideoTime.text = durationString;
}

-(void)resetPlayView {
    [self.player pause];
    [self removeProgressTimer];
    [self.player replaceCurrentItemWithPlayerItem:nil];
    _videoUrl = nil;
    [self.progressView startAnimating];
    self.progressSlider.value = 0.0;
    self.cacheSlider.value = 0.0;
    self.totalVideoTime.text = @"00:00";
    self.currentVideoTime.text = @"00:00";
    
}



- (void) removeTimer {
    
    [self.autoDismissTimer invalidate];
    self.autoDismissTimer = nil;
    [self removeProgressTimer];
}

#pragma mark - setter

- (void)setVideoUrl:(NSString *)videoUrl {
    
    _videoUrl = videoUrl;
    [self.playerItem removeObserver:self forKeyPath:@"status"];
    [self.playerItem removeObserver:self forKeyPath:@"playbackBufferEmpty"];
    [self.playerItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp"];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [self.progressView startAnimating];
    self.playerItem = [AVPlayerItem playerItemWithURL:[NSURL URLWithString:videoUrl]];
    [self.player replaceCurrentItemWithPlayerItem:self.playerItem];
    
    // 添加视频播放结束通知
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(moviePlayDidEnd:) name:AVPlayerItemDidPlayToEndTimeNotification object:self.playerItem];
    [self.playerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    // 缓冲区空了，需要等待数据
    [self.playerItem addObserver:self forKeyPath:@"playbackBufferEmpty" options: NSKeyValueObservingOptionNew context:PlayViewStatusObservationContext];
    // 缓冲区有足够数据可以播放了
    [self.playerItem addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options: NSKeyValueObservingOptionNew context:PlayViewStatusObservationContext];
    
}

- (void)setVideoTitle:(NSString *)videoTitle {
    _videoTitle = videoTitle;
    self.titleLabel.text = _videoTitle;
}

- (void)setIsPortrait:(BOOL)isPortrait {
    _isPortrait = isPortrait;
    
    if (_isPortrait) {
        self.topStatusBar.backgroundColor = [UIColor clearColor];
        self.titleLabel.hidden = YES;
        self.shareBtn.hidden = YES;
        [UIApplication sharedApplication].statusBarHidden = NO;
        self.backButton.alpha = 1.0;
        [self.fullScreenButton setImage:[UIImage imageNamed:@"videoDetail_fullScreen"] forState:UIControlStateNormal];

    }else{
        self.topStatusBar.backgroundColor = [UIColor blackColor];
        self.titleLabel.hidden = NO;
        self.shareBtn.hidden = NO;
        
        if (self.topBar.alpha == 0.0) {
            self.backButton.alpha = 0.0;
            [UIApplication sharedApplication].statusBarHidden = YES;
            
        }else{
            self.backButton.alpha = 1.0;
            [UIApplication sharedApplication].statusBarHidden = NO;
            
        }
        [self.fullScreenButton setImage:[UIImage imageNamed:@"videoDetail_portraitScreen"] forState:UIControlStateNormal];
    }
}

- (void)setNetState:(MmiaPlayerNetState)netState {
    _netState = netState;
}


#pragma mark - getter
- (UIView *)topBar
{
    if (!_topBar) {
        WeakSelf(wself);
        
        _topBar = [[UIView alloc] init];
        
        self.topStatusBar = [[UIView alloc] init];
        self.topStatusBar.backgroundColor = [UIColor blackColor];
        [_topBar addSubview:self.topStatusBar];
        [self.topStatusBar mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.right.top.equalTo(_topBar);
            make.height.mas_equalTo(@20);
        }];
        
        UIImageView * backImg = [[UIImageView alloc] init];
        backImg.image = [UIImage imageNamed:@"videoDetail_topBackImg"];
        [_topBar addSubview:backImg];
        [backImg mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.right.top.equalTo(_topBar);
            make.height.mas_equalTo(58);
        }];
        
        [_topBar addSubview:self.shareBtn];
        [self.shareBtn mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(_topBar).offset(20);
            make.right.equalTo(_topBar);
            make.width.mas_equalTo(@52);
            make.height.mas_equalTo(@44.5);
        }];
        [_topBar addSubview:self.titleLabel];
        [self.titleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.top.equalTo(_topBar).offset(20);
            make.left.equalTo(_topBar).offset(44);
            make.right.mas_equalTo(wself.shareBtn.mas_left).offset(0);
            make.height.mas_equalTo(@45);
        }];
        _topBar.alpha = 0.0;
    }
    return _topBar;
}

- (UIView *)bottomBar
{
    if (!_bottomBar) {
        _bottomBar = [[UIView alloc] init];
        _bottomBar.backgroundColor = ColorWithHexRGBA(0x000000, 0.8);
        _bottomBar.alpha = 0.0;
    }
    return _bottomBar;
}

- (UIButton *)backButton {
    if (!_backButton) {
        _backButton = [[UIButton alloc] init];
        [_backButton setImage:[UIImage imageNamed:@"videoDetail_popVC"] forState:UIControlStateNormal];
        _backButton.imageEdgeInsets = UIEdgeInsetsMake(12, 15, 12, 15);
        [_backButton addTarget:self action:@selector(MmiaVideoPlayerControlViewBackButtonClick) forControlEvents:UIControlEventTouchUpInside];
    }
    return _backButton;
}

- (UILabel *)titleLabel{
    if (!_titleLabel) {
        _titleLabel = [[UILabel alloc] init];
        _titleLabel.textAlignment = NSTextAlignmentLeft;
        _titleLabel.font = [UIFont systemFontOfSize:17];
        _titleLabel.text = @"";
        _titleLabel.textColor = ColorWithHexRGB(0xffffff);
    }
    return _titleLabel;
}

- (UIButton *)shareBtn {
    if (!_shareBtn) {
        _shareBtn = [[UIButton alloc] init];
        [_shareBtn setImage:[UIImage imageNamed:@"videoDetail_share"] forState:UIControlStateNormal];
        _shareBtn.imageEdgeInsets = UIEdgeInsetsMake(12.5, 15, 12.5, 15);
        [_shareBtn addTarget:self action:@selector(shareBtnClick) forControlEvents:UIControlEventTouchUpInside];
        _shareBtn.enabled = NO;
    }
    return _shareBtn;
}


- (UIButton *)playOrPauseButton
{
    if (!_playOrPauseButton) {
        _playOrPauseButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [_playOrPauseButton setImage:[UIImage imageNamed:@"videoDetail_pause"] forState:UIControlStateNormal];
        [_playOrPauseButton addTarget:self action:@selector(playOrPauseButtonClick:) forControlEvents:UIControlEventTouchUpInside];
        _playOrPauseButton.alpha = 0.0;
    }
    return _playOrPauseButton;
}



- (UIButton *)fullScreenButton
{
    if (!_fullScreenButton) {
        _fullScreenButton = [[UIButton alloc] init];
        _fullScreenButton.imageEdgeInsets = UIEdgeInsetsMake(13, 13, 13, 13);
        [_fullScreenButton setImage:[UIImage imageNamed:@"videoDetail_fullScreen"] forState:UIControlStateNormal];
        [_fullScreenButton addTarget:self action:@selector(fullScreenButtonClick) forControlEvents:UIControlEventTouchUpInside];
    }
    return _fullScreenButton;
}


- (UISlider *)cacheSlider {
    if (!_cacheSlider) {
        _cacheSlider = [[UISlider alloc] init];
        _cacheSlider.userInteractionEnabled = NO;
        [_cacheSlider setThumbImage:[UIImage imageNamed:@"videoDetail_cachePoint"] forState:UIControlStateNormal];
        [_cacheSlider setMinimumTrackTintColor:ColorWithHexRGB(0x555555)];
        [_cacheSlider setMaximumTrackTintColor:ColorWithHexRGB(0x3b3b3b)];
        _cacheSlider.value = 0.f;
        _cacheSlider.continuous = YES;
    }
    return _cacheSlider;
    
}

- (UISlider *)progressSlider
{
    if (!_progressSlider) {
        _progressSlider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, self.bounds.size.width, 10)];
        [_progressSlider setThumbImage:[UIImage imageNamed:@"videoDetail_progressPoint"] forState:UIControlStateNormal];
        [_progressSlider setMinimumTrackTintColor:ColorWithHexRGB(0xff4a46)];
        [_progressSlider setMaximumTrackTintColor:[UIColor clearColor]];
        _progressSlider.value = 0.f;
        _progressSlider.continuous = YES;
        _progressSlider.userInteractionEnabled = NO;
        [_progressSlider addTarget:self action:@selector(progressSliderTouchUpInside) forControlEvents:UIControlEventTouchUpInside];
        [_progressSlider addTarget:self action:@selector(progressSliderTouchDown) forControlEvents:UIControlEventTouchDown];
        [_progressSlider addTarget:self action:@selector(progressSliderValueChanged) forControlEvents:UIControlEventValueChanged];
        [_progressSlider addTarget:self action:@selector(progressSliderTouchUpInside) forControlEvents:UIControlEventTouchUpOutside];
    }
    return _progressSlider;
}

- (UILabel *)currentVideoTime{
    if (!_currentVideoTime) {
        _currentVideoTime = [[UILabel alloc] init];
        _currentVideoTime.textAlignment = NSTextAlignmentCenter;
        _currentVideoTime.textColor = ColorWithHexRGB(0xffffff);
        _currentVideoTime.font = [UIFont systemFontOfSize:10];
        _currentVideoTime.text = @"00:00";
    }
    return _currentVideoTime;
}

- (UILabel *)totalVideoTime {
    if (!_totalVideoTime) {
        _totalVideoTime = [[UILabel alloc] init];
        _totalVideoTime.textAlignment = NSTextAlignmentCenter;
        _totalVideoTime.textColor = ColorWithHexRGB(0xffffff);
        _totalVideoTime.font = [UIFont systemFontOfSize:10];
        _totalVideoTime.text = @"00:00";
    }
    return _totalVideoTime;
}

- (UIView *)shareView {
    if (!_shareView) {
        
        _shareView = [[UIView alloc] initWithFrame:self.bounds];
        
        _shareView.backgroundColor = [UIColor clearColor];
        UITapGestureRecognizer * tapGes = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(shareViewTapAction)];

        [_shareView addGestureRecognizer:tapGes];
        
        _shareBtnContainer = [[UIView alloc] initWithFrame:CGRectMake(self.bounds.size.width, 0, 320, self.bounds.size.height)];
        UITapGestureRecognizer * shareContainerTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(shareContainerTapAction)];
        [_shareBtnContainer addGestureRecognizer:shareContainerTap];
        
        [_shareView addSubview:_shareBtnContainer];
        _shareBtnContainer.backgroundColor = ColorWithHexRGBA(0x000000, 0.75);
    
        //分享到
        UILabel * shareToLabel = [[UILabel alloc] init];
        shareToLabel.backgroundColor = [UIColor clearColor];
        shareToLabel.text = @"分享到";
        shareToLabel.textColor = ColorWithHexRGB(0xffffff);
        shareToLabel.font = [UIFont systemFontOfSize:17];
        shareToLabel.textAlignment = NSTextAlignmentCenter;
        [_shareBtnContainer addSubview:shareToLabel];
        [shareToLabel mas_makeConstraints:^(MASConstraintMaker *make) {
            make.left.right.equalTo(_shareBtnContainer);
            make.top.equalTo(_shareBtnContainer).offset(70);
            make.height.mas_equalTo(@18);
        }];
    
        //添加分享按钮
        NSArray * imgNameArray = @[@"share_wechat_session",@"videoDetail_circleOfFriends",@"share_sina",@"share_qq"];
        NSArray * zhNameArray = @[@"微信好友",@"微信朋友圈",@"新浪微博",@"腾讯QQ"];
        [self addShareButtonsWithContainerView:_shareBtnContainer andImageNameArray:imgNameArray andZhNameArray:zhNameArray];
        
    }
    return _shareView;
}

- (UIView *)voiceGuideView {
    if (!_voiceGuideView) {
        _voiceGuideView = [[UIView alloc] init];
        _voiceGuideView.backgroundColor = ColorWithHexRGB(0x000000);
        _voiceGuideView.alpha = 0.6;
        
        UIImageView * voiceImg = [[UIImageView alloc] init];
        voiceImg.image = [UIImage imageNamed:@"videoDetail_voiceGuide"];
        [_voiceGuideView addSubview:voiceImg];
        [voiceImg mas_makeConstraints:^(MASConstraintMaker *make) {
            make.center.equalTo(_voiceGuideView);
            make.width.mas_equalTo(@50);
            make.height.mas_equalTo(@115);
        }];
        
        UITapGestureRecognizer * tapGes = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(voiceGuideViewTap:)];
        [_voiceGuideView addGestureRecognizer:tapGes];
    }
    return _voiceGuideView;
}

//点击退出分享
- (void) shareViewTapAction {
    WeakSelf(wself);
    [UIView animateWithDuration:0.4 animations:^{
        _shareBtnContainer.left = wself.bounds.size.width;
    } completion:^(BOOL finished) {
        [wself.shareView removeFromSuperview];
    }];
}

- (void) addShareButtonsWithContainerView: (UIView *) containerView andImageNameArray:(NSArray *) imgNameArray andZhNameArray: (NSArray *) zhNameArray {
    
    for (int i = 0; i < imgNameArray.count ; i++) {
        
        UIButton *button =[UIButton buttonWithType:UIButtonTypeCustom];
        [button setImage:[UIImage imageNamed:imgNameArray[i]] forState:UIControlStateNormal];
        [button setTitle:zhNameArray[i] forState:UIControlStateNormal];
        button.titleLabel.font = UIFontSystem(13);
        [button setImageEdgeInsets:UIEdgeInsetsMake(-20, 8, 0, 0)];
        [button setTitleEdgeInsets:UIEdgeInsetsMake(65, -55, 0, 0)];
        [containerView addSubview:button];
        
        button.tag = i;
        
        [button mas_makeConstraints:^(MASConstraintMaker *make) {
            make.centerY.equalTo(containerView);
            make.width.mas_equalTo(@75.25);
            make.height.mas_equalTo(@77);
            make.left.equalTo(containerView).offset(9.5 + i * 75.25);
        }];
        [button addTarget:self action:@selector(shareButtonClick:) forControlEvents:UIControlEventTouchUpInside];
        
    }
    
    if (![TencentOAuth iphoneQQInstalled]) {
        UIButton *btn = (UIButton *)[containerView viewWithTag:3];
        btn.enabled = NO;
    }

}

//分享按钮的点击
- (void)shareButtonClick:(UIButton *)button
{
    [self shareViewTapAction];
    if (self.delegate) {
        [self.delegate MmiaVideoPlayerControlViewShareButtonClick:button.tag];
    }
}

- (void) shareButtonTap:(UITapGestureRecognizer *) tapGes {
    [self shareViewTapAction];
    if (self.delegate) {
        [self.delegate MmiaVideoPlayerControlViewShareButtonClick:tapGes.view.tag];
    }
}

- (void ) shareContainerTapAction {
}

//改变横屏状态下的分享界面位置
- (void) dismissShareViewLandscape{
    _shareBtnContainer.left = [UIScreen mainScreen].bounds.size.height;
    //这里不要调用 self.shareView
    [_shareView removeFromSuperview];
}

#pragma mark - initialize
- (void) initialize {
    //设置静音状态也可播放声音
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:nil];
    
    self.player = [[AVPlayer alloc] init];
    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
    [self.layer addSublayer:self.playerLayer];
    
    
    self.backgroundColor = [UIColor blackColor];
    [self addSubview:self.topBar];
    WeakSelf(wself);
    [self.topBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.right.equalTo(wself);
        make.top.equalTo(wself);
        make.height.mas_equalTo(@68);
    }];
    
    [self addSubview:self.backButton];
    [self.backButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(wself);
        make.top.equalTo(wself).offset(20);
        make.width.mas_equalTo(@43.5);
        make.height.mas_equalTo(@47.5);
    }];
    
    
    
    [self addSubview:self.bottomBar];
    
    [self.bottomBar mas_makeConstraints:^(MASConstraintMaker *make) {
        make.left.bottom.right.equalTo(wself);
        make.height.mas_equalTo(@45);
    }];
    
    [self addSubview:self.playOrPauseButton];
    
    self.progressView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    [self addSubview:self.progressView];
    [self.progressView startAnimating];
    self.progressView.hidesWhenStopped = YES;
    [self.progressView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(wself);
    }];
    
    
    [self.bottomBar addSubview:self.fullScreenButton];
    [self.fullScreenButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerY.equalTo(wself.bottomBar);
        make.right.equalTo(wself).offset(-4);
        make.width.height.mas_equalTo(@39);
    }];
    
    
    
    [self.bottomBar addSubview:self.totalVideoTime];
    [self.totalVideoTime mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerY.equalTo(wself.bottomBar);
        make.right.equalTo(wself.bottomBar).offset(-43);
        make.width.mas_equalTo(@32);
        make.height.mas_equalTo(@12);
    }];
    
    
    
    [self.bottomBar addSubview:self.currentVideoTime];
    [self.currentVideoTime mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerY.equalTo(wself.bottomBar);
        make.left.equalTo(wself.bottomBar).offset(17);
        make.width.mas_equalTo(@32);
        make.height.mas_equalTo(@12);
    }];
    
    [self.bottomBar addSubview:self.cacheSlider];
    [self.cacheSlider mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerY.equalTo(wself.bottomBar);
        make.left.equalTo(wself.bottomBar).offset(66);
        make.right.equalTo(wself.bottomBar).offset(-98);
        make.height.mas_equalTo(@3);
    }];
    
    
    [self.bottomBar addSubview:self.progressSlider];
    [self.progressSlider mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerY.equalTo(wself.bottomBar);
        make.left.equalTo(wself.bottomBar).offset(66);
        make.right.equalTo(wself.bottomBar).offset(-96);
    }];
    
    
    [self addSubview:self.playOrPauseButton];
    [self.playOrPauseButton mas_makeConstraints:^(MASConstraintMaker *make) {
        make.center.equalTo(wself);
        make.width.height.mas_equalTo(@43.5);
    }];
    
    //         单击的 Recognizer
    singleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleSingleTap:)];
    singleTap.numberOfTapsRequired = 1; // 单击
    singleTap.numberOfTouchesRequired = 1;
    [self addGestureRecognizer:singleTap];
    
    [self.autoDismissTimer invalidate];
    self.autoDismissTimer = nil;
    self.autoDismissTimer = [NSTimer timerWithTimeInterval:8.0 target:self selector:@selector(autoDismissBottomView:) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:self.autoDismissTimer forMode:NSDefaultRunLoopMode];
    
    AFNetworkReachabilityManager *reachabilityManager = [AFNetworkReachabilityManager sharedManager];
    [reachabilityManager startMonitoring];
    [reachabilityManager setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
        wself.netState = status;
    }];
    
    //添加一个声音引导层
    [self addVoiceControlGuide];
   
}


@end
