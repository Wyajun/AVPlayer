//
//  MmiaVideoPlayView.h
//  MMIA
//
//  Created by wyl on 16/8/14.
//  Copyright © 2016年 MMIA. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
@protocol  MmiaVideoPlayViewDelegate<NSObject>
//返回按钮
- (void) MmiaVideoPlayerControlViewBackButtonClick;
//全屏按钮点击
- (void) MmiaVideoPlayerControlViewFullScreenButtonClick;
//视频播放结束
- (void) MmiaVideoPlayerControlViewFinishPlay;
//分享按钮的点击
- (void) MmiaVideoPlayerControlViewShareButtonClick:(NSInteger) tag;
//重新连上网络的情况下,点击播放按钮,则重新刷新视频详情界面的数据
- (void) MmiaVideoPlayerControlViewPlayButtonClickWhenNetworkNormal;

@end

@interface MmiaVideoPlayView : UIView
@property (nonatomic , strong) NSString * videoUrl;
@property (nonatomic , copy) NSString * videoTitle;
@property (nonatomic, strong,readonly) UIButton * backButton;
@property (nonatomic, strong,readonly) UIButton *fullScreenButton;
@property (nonatomic, strong) UISlider *progressSlider;
@property (nonatomic, weak) id<MmiaVideoPlayViewDelegate>delegate;
//分享按钮
@property (nonatomic, strong) UIButton * shareBtn;

@property (nonatomic, assign) BOOL isPortrait;

//此时播放器的状态是否是暂停
@property (nonatomic , assign) BOOL isVideoPause;

//暂停
- (void) pause ;
//播放
- (void) play ;

//去除定时器
- (void) removeTimer;

//改变横屏状态下的分享界面位置
- (void) dismissShareViewLandscape ;

//网络情况差的时候显示所有的工具栏
- (void) showAllToolBar ;

//重置播放器
-(void)resetPlayView ;

@end
