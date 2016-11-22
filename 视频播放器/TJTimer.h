//
//  TJTimer.h
//  TuJia
//
//  Created by 王亚军 on 16/10/19.
//  Copyright © 2016年 途家. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface TJTimer : NSObject
+ (TJTimer *)timerWithInterval:(uint64_t)interval
                        leeway:(uint64_t)leeway
                         queue:(dispatch_queue_t)queue
                         block:(dispatch_block_t)block;

+ (TJTimer *)timerWithStart:(uint64_t)start
                     leeway:(uint64_t)leeway
                      queue:(dispatch_queue_t)queue
                      block:(dispatch_block_t)block;
/*
 * 创建完后立刻执行block
 * interval 时间间隔
 * leeway   允许误差
 * queue    回调队列
 * block    执行block
 */
- (id)initWithInterval:(uint64_t)interval
                leeway:(uint64_t)leeway
                 queue:(dispatch_queue_t)queue
                 block:(dispatch_block_t)block;
/*
 * 创建完后过下一个时间间隔执行block
 * interval 时间间隔
 * leeway   允许误差
 * queue    回调队列
 * block    执行block
 */
- (id)initWithStart:(uint64_t)start
             leeway:(uint64_t)leeway
              queue:(dispatch_queue_t)queue
              block:(dispatch_block_t)block;

- (void)resume;
- (void)suspend;
- (void)cancel;


@end
