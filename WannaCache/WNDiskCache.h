//
//  WNDiskCache.h
//  WannaCache
//
//  Created by X-Liang on 16/4/29.
//  Copyright © 2016年 X-Liang. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "WNCacheObjectSubscripting.h"

@class WNDiskCache;

typedef void (^WNDiskCacheBlcok)(WNDiskCache * _Nonnull cache);

typedef void (^WNDiskCacheObjectBlock)(WNDiskCache *_Nonnull cache, NSString * _Nonnull key, id <NSCoding> __nullable object, NSURL * __nullable flieURL);

@interface WNDiskCache : NSObject<WNCacheObjectSubscripting>

@property (readonly, nonnull) NSString *name;

@property (readonly, nonnull) NSURL *cacheURL;

@property (readonly) NSUInteger byteCount;

@property (assign) NSUInteger byteLimit;

@property (assign) NSTimeInterval ageLimit;

//???: 
#if TARGET_OS_IPHONE
@property (assign) NSDataWritingOptions writingProtectionOption;
#endif

@property (assign, getter=isTTLCache) BOOL ttlCache;

@property (copy) WNDiskCacheObjectBlock __nullable willAddObjectBlock;

@property (copy) WNDiskCacheObjectBlock __nullable willRemoveObjectBlock;

@property (copy) WNDiskCacheBlcok __nullable willRemoveAllObjectsBlock;

@property (copy) WNDiskCacheObjectBlock __nullable didAddObjectBlock;

@property (copy) WNDiskCacheObjectBlock __nullable didRemoveObjectBlock;

@property (copy) WNDiskCacheBlcok __nullable didRemoveAllObjectsBlock;

+ (instancetype __nullable)sharedCache;

+ (void)emptyTrash;

- (instancetype __nullable)initWithName:(NSString * __nullable)name;

- (instancetype __nullable)initWithName:(NSString * __nullable)name rootPath:(NSString *__nullable)rootPath;

- (void)fileURLForKey:(NSString * __nullable)key block:(WNDiskCacheObjectBlock __nullable)block;

- (void)objectForKey:(NSString * __nullable)key block:(WNDiskCacheObjectBlock __nullable)block;

- (void)setObject:(id <NSCoding> __nullable)object forKey:(NSString * __nullable)key block:(WNDiskCacheObjectBlock __nullable)block;

- (void)removeObjectForKey:(NSString * __nullable)key block:(WNDiskCacheObjectBlock __nullable)block;

- (void)removeAllObjects:(WNDiskCacheBlcok __nullable)block;

- (void)trimToDate:(NSDate * __nullable)trimDate block:(WNDiskCacheBlcok __nullable)block;

- (void)synchronouslyLockFileAccessWhileExecutingBlock:(void(^ __nullable)(WNDiskCache * __nullable diskCache) )block;

- (__nullable id<NSCoding>)objectForKey:(NSString * __nullable)key;

- (void)setObject:(id <NSCoding> __nullable)object forKey:(NSString * __nullable)key;

- (void)removeObjectForKey:(NSString * __nullable)key;

- (void)trimToDate:(NSDate * __nullable)trimDate;

- (void)removeAllObjects;

@end
