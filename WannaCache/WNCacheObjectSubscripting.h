//
//  WNCacheObjectSubscripting.h
//  WannaCache
//
//  Created by X-Liang on 16/4/28.
//  Copyright © 2016年 X-Liang. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol WNCacheObjectSubscripting <NSObject>

@required
/**
 *  下标脚本的取值操作, 实现该方法, 可以通过下标脚本获得存储的缓存值
 *  就像这样获得缓存值 id obj = cache[@"key"]
 *  @param key 缓存对象关联的 key
 *
 *  @return  指定 key 的缓存对象
 */
- (id)objectForKeyedSubscript:(NSString *)key;

/**
 *  下标脚本的设置值操作, 实现该方法可以通过下标脚本设置缓存
 *  像这样 cache[@"key"] = object
 *  @param obj 要缓存的对象
 *  @param key 缓存对象关联的 key
 */
- (void)setObject:(id)obj forKeyedSubscript:(NSString *)key;

/**
 *  以上两个方法应该确保线程安全
 */
@end
