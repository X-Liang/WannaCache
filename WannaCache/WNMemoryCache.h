//
//  WNMemoryCache.h
//  WannaCache
//
//  Created by X-Liang on 16/4/27.
//  Copyright © 2016年 X-Liang. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "WNCacheObjectSubscripting.h"

@class WNMemoryCache;
typedef void (^WNMemoryCacheBlcok)(WNMemoryCache * _Nonnull cache);

typedef void (^WNMemoryCacheObjectBlock)(WNMemoryCache *_Nonnull cache, NSString * _Nonnull key, id __nullable object);

@interface WNMemoryCache : NSObject<WNCacheObjectSubscripting>

@property (strong, readonly) __nonnull dispatch_queue_t concurrentQueue;
/** 内存缓存所占的总容量*/
@property (assign, readonly) NSUInteger totalCost;
@property (assign) NSUInteger costLimit;
/**
 *  缓存存活时间, 如果设置为一个大于0的值, 就被开启为 TTL 缓存(指定存活期的缓存),即如果 ageLimit > 0 => ttlCache = YES;
 */
@property (assign) NSTimeInterval ageLimit;
/**
 *  如果指定为 YES, 缓存行为就像 TTL 缓存, 缓存只在指定的存活期(ageLimit)内存活
 * Accessing an object in the cache does not extend that object's lifetime in the cache
 * When attempting to access an object in the cache that has lived longer than self.ageLimit,
 * the cache will behave as if the object does not exist
 */
@property (assign, getter=isTTLCache) BOOL ttlCache;
/** 是否当内存警告时移除缓存, 默认 YES*/
@property (assign) BOOL removeAllObjectOnMemoryWoring;
/** 是否当进入到后台时移除缓存, 默认 YES*/
@property (assign) BOOL removeAllObjectOnEnteringBackground;

@property (copy) WNMemoryCacheObjectBlock __nullable willAddObjectBlock;

@property (copy) WNMemoryCacheObjectBlock __nullable willRemoveObjectBlock;

@property (copy) WNMemoryCacheObjectBlock __nullable didAddObjectBlock;

@property (copy) WNMemoryCacheObjectBlock __nullable didRemoveObjectBlock;

@property (copy) WNMemoryCacheBlcok __nullable willRemoveAllObjectsBlock;
@property (copy) WNMemoryCacheBlcok __nullable didRemoveAllObjectsBlock;
@property (copy) WNMemoryCacheBlcok __nullable didReceiveMemoryWarningBlock;
@property (copy) WNMemoryCacheBlcok __nullable didEnterBackgroundBlock;

+ (_Nonnull instancetype)shareInstance;
#pragma mark - Async Method
/**
 *  异步读取缓存的对象
 *
 *  @param key      缓存对象对应的 Key
 *  @param callBack 缓存对象读取成功后回调
 */
- (void)objectForKey:(NSString *__nullable)key block:(WNMemoryCacheObjectBlock __nullable)callBack;
/**
 *  异步写入要缓存的对象
 *
 *  @param object   要缓存的对象
 *  @param key      缓存对象对应的 Key
 *  @param callBack 缓存成功后回调
 */
- (void)setObject:(id __nullable)object forKey:(NSString * __nullable)key blcok:(WNMemoryCacheObjectBlock __nullable)callBack;
/**
 *  异步写入要缓存的对象
 *
 *  @param object   要缓存的对象
 *  @param key      缓存对象对应的 Key
 *  @param cost     缓存花费的代价
 *  @param callBack 缓存成功后回调
 */
- (void)setObject:(id __nullable)object forKey:(NSString * __nullable)key withCost:(NSUInteger)cost blcok:(WNMemoryCacheObjectBlock __nullable)callBack;
/**
 *  异步移除指定 key 的缓存
 */
- (void)removeObjectForKey:(NSString * __nullable)key block:(WNMemoryCacheObjectBlock __nullable)callBack;
- (void)trimToDate:(NSDate * __nullable)trimDate block:(WNMemoryCacheBlcok __nullable)callBack;
- (void)trimToCostLimit:(NSUInteger)cost block:(WNMemoryCacheBlcok __nullable)callBack;
- (void)trimCostByDateToCostLimit:(NSUInteger)costLimt blcok:(WNMemoryCacheBlcok __nullable)callBack;
- (void)removeAllObjects:(WNMemoryCacheBlcok __nullable)callBack;
- (void)enumerateObjectsWithBlock:(WNMemoryCacheObjectBlock __nullable)optionBlock completionBlcok:(WNMemoryCacheBlcok __nullable)completionBlock;

#pragma mark - Sync Method
/**
 *  线程安全的缓存对象的读取操作, 所有关于缓存读取的操作都是调用该方法
 *
 *  @param key 要获得的缓存对应的 key
 *
 *  @return 缓存对象
 */
- (__nullable id)objectForKey:(NSString * __nullable)key;
/**
 *  线程安全的缓存存储操作, 所有的缓存写入都是调用该方法
 *
 *  @param object 要缓存的对象
 *  @param key    缓存对象对应的 Key
 *  @param cost   缓存的代价
 */
- (void)setObject:(id __nullable)object forKey:(NSString * __nullable)key withCost:(NSUInteger)cost;
- (void)enumerateObjectsWithBlock:(WNMemoryCacheObjectBlock __nullable)callBack;
- (void)removeObjectForKey:(NSString * __nullable)key;
- (void)removeAllObjects;
- (void)trimToDate:(NSDate * __nullable)date;
- (void)trimToCost:(NSUInteger)cost;
@end
