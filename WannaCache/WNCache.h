//
//  WNCache.h
//  WannaCache
//
//  Created by X-Liang on 16/4/27.
//  Copyright © 2016年 X-Liang. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "WNCacheObjectSubscripting.h"
@class WNDiskCache, WNMemoryCache, WNCache;

typedef void (^WNCacheBlock)(WNCache * __nullable cache);

typedef void (^WNCacheObjectBlock)(WNCache *__nullable cache, NSString * __nullable key, id __nullable object);

@interface WNCache : NSObject<WNCacheObjectSubscripting>
@property (readonly, nullable) NSString *name;
@property (readonly, strong, nonnull) WNDiskCache *diskCache;
@property (readonly, strong, nonnull) WNMemoryCache *memoryCache;
+ (__nullable instancetype)sharedCache;

- (__nullable instancetype)init NS_UNAVAILABLE;

- (__nullable instancetype)initWithName:(NSString * __nullable)name;

- (__nullable instancetype)initWithName:(NSString * __nullable)name rootPath:(NSString * __nullable)rootPath NS_DESIGNATED_INITIALIZER;

- (void)objectForKey:(NSString * __nullable)key block:(WNCacheObjectBlock __nullable)block;

- (void)setObject:(id <NSCoding> __nullable)object forKey:(NSString * __nullable)key block:(nullable WNCacheObjectBlock)block;

- (void)removeObjectForKey:(NSString * __nullable)key block:(nullable WNCacheObjectBlock)block;

- (void)trimToDate:(NSDate * __nullable)date block:(nullable WNCacheBlock)block;

- (void)removeAllObjects:(nullable WNCacheBlock)block;

#pragma mark -
/// @name Synchronous Methods
- (__nullable id)objectForKey:(NSString * __nullable)key;

- (void)setObject:(id <NSCoding> __nullable)object forKey:(NSString * __nullable)key;

- (void)removeObjectForKey:(NSString * __nullable)key;

- (void)trimToDate:(NSDate * __nullable)date;

- (void)removeAllObjects;

@end
