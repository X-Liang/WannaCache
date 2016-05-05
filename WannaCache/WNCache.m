//
//  WNCache.m
//  WannaCache
//
//  Created by X-Liang on 16/4/27.
//  Copyright © 2016年 X-Liang. All rights reserved.
//

#import "WNCache.h"
#import "WNDiskCache.h"
#import "WNMemoryCache.h"

static NSString * const WannaCachePrefix = @"com.wanna.WannaDiskCaches";
static NSString * const WannaCacheSharedName = @"WannaCacheShared";

@interface WNCache ()
#if OS_OBJECT_USE_OBJC
@property (nonatomic, strong) dispatch_queue_t concurrentQueue;
#else
@property (nonatomic, assign) dispatch_queue_t concurrentQueue;
#endif
@end

@implementation WNCache

#if !OS_OBJECT_USE_OBJC
- (void)dealloc {
    dispatch_release(_concurrentQueue);
    _concurrentQueue = nil;
}
#endif

- (instancetype)init {
    @throw [NSException exceptionWithName:@"Must initialize with a name" reason:@"WNCache must be initialized with a name. Call initWithName: instead." userInfo:nil];
    return [self initWithName:@""];
}

- (instancetype)initWithName:(NSString *)name {
    return [self initWithName:name rootPath:[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject]];
}

- (instancetype)initWithName:(NSString *)name rootPath:(NSString *)path {
    if (!name) {
        return nil;
    }
    
    if (self = [super init]) {
        _name = [name copy];
        NSString *queueName = [[NSString alloc] initWithFormat:@"%@.%p", WannaCachePrefix, self];
        _concurrentQueue = dispatch_queue_create([[NSString stringWithFormat:@"%@ Asynchronous Queue", queueName] UTF8String],
                                                 DISPATCH_QUEUE_CONCURRENT);
        _diskCache = [[WNDiskCache alloc] initWithName:_name rootPath:path];
        _memoryCache = [[WNMemoryCache alloc] init];
    }
    return self;
}

+ (instancetype)sharedCache {
    static WNCache *cache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [[WNCache alloc] initWithName:WannaCacheSharedName];
    });
    return cache;
}

#pragma mark - Public Asynchronous Methods
- (void)objectForKey:(NSString *)key block:(WNCacheObjectBlock)block {
    if (!key || !block) {
        return ;
    }
    __weak typeof(self)weakSelf = self;
    dispatch_async(_concurrentQueue, ^{
        __strong typeof(weakSelf)strongSelf = weakSelf;
        if (!strongSelf) return ;
        //???:
        [strongSelf->_memoryCache objectForKey:key
                                         block:^(WNMemoryCache * _Nonnull cache, NSString * _Nonnull memoryCacheKey, id  _Nullable memoryCacheObject) {
                                             __strong typeof(weakSelf)strongSelf = weakSelf;
                                             if (!strongSelf) return ;
                                             
                                             if (memoryCacheObject) {
                                                 [strongSelf->_diskCache fileURLForKey:memoryCacheKey
                                                                                 block:^(WNDiskCache * _Nonnull cache, NSString * _Nonnull key, id<NSCoding>  _Nullable object, NSURL * _Nullable flieURL) {
                                                                                     
                                                                                 }];
                                                 dispatch_async(self->_concurrentQueue, ^{
                                                     __strong typeof(weakSelf)strongSelf = weakSelf;
                                                     if (strongSelf) {
                                                         block(strongSelf, memoryCacheKey, memoryCacheObject);
                                                     }
                                                 });
                                             } else {
                                                 [strongSelf->_diskCache objectForKey:memoryCacheKey block:^(WNDiskCache * _Nonnull cache, NSString * _Nonnull key, id<NSCoding>  _Nullable object, NSURL * _Nullable flieURL) {
                                                     __strong typeof(weakSelf)strongSelf = weakSelf;
                                                     if (!strongSelf) {
                                                         return ;
                                                     }
                                                     
                                                     [strongSelf->_memoryCache setObject:cache forKey:key blcok:nil];
                                                     
                                                     dispatch_async(strongSelf->_concurrentQueue, ^{
                                                         __strong typeof(weakSelf)strongSelf = weakSelf;
                                                         if (block) {
                                                             block(strongSelf, key, object);
                                                         }
                                                     });
                                                 }];
                                             }
                                         }];
    });
}

- (void)setObject:(id)obj forKeyedSubscript:(NSString *)key {
    [self setObject:obj forKey:key];
}

- (void)setObject:(id<NSCoding>)object forKey:(NSString *)key block:(WNCacheObjectBlock)block {
    if (!key || !block) {
        return;
    }
    dispatch_group_t group = nil;
    WNMemoryCacheObjectBlock memoryBlock = nil;
    WNDiskCacheObjectBlock diskBlock = nil;
    
    if (block) {
        group = dispatch_group_create();
        dispatch_group_enter(group);
        memoryBlock = ^(WNMemoryCache *memoryCache, NSString *memoryCacheKey, id memoryCacheObject){
            dispatch_group_leave(group);
        };
        
        dispatch_group_enter(group);
        diskBlock = ^(WNDiskCache *diskCache, NSString *diskCacheKey, id<NSCoding>diskCacheObject, NSURL *diskCacheFileURL){
            dispatch_group_leave(group);
        };
    }
    
    [_memoryCache setObject:object forKey:key blcok:memoryBlock];
    [_diskCache setObject:object forKey:key block:diskBlock];
    
    if (group) {
        __weak typeof(self)weakSelf = self;
        dispatch_notify(group, _concurrentQueue, ^{
            __weak typeof(self)strongSelf = weakSelf;
            if (strongSelf) {
                block(strongSelf, key, object);
            }
        });
#if !OS_OBJECT_USE_OBJC
        dispatch_release(group);
#endif
    }
}

- (void)removeObjectForKey:(NSString *)key block:(WNCacheObjectBlock)block {
    if (!key) {
        return;
    }
    dispatch_group_t group = nil;
    WNMemoryCacheObjectBlock memoryBlock = nil;
    WNDiskCacheObjectBlock diskBlock = nil;
    
    if (block) {
        group = dispatch_group_create();
        dispatch_group_enter(group);
        memoryBlock = ^(WNMemoryCache *memoryCache, NSString *memoryCacheKey, id memoryCacheObject){
            dispatch_group_leave(group);
        };
        
        dispatch_group_enter(group);
        diskBlock = ^(WNDiskCache *diskCache, NSString *diskCacheKey, id<NSCoding>diskCacheObject, NSURL *diskCacheFileURL){
            dispatch_group_leave(group);
        };
    }

    [_memoryCache removeObjectForKey:key block:memoryBlock];
    [_diskCache removeObjectForKey:key block:diskBlock];
    
    if (group) {
        __weak typeof(self)weakSelf = self;
        dispatch_group_notify(group, _concurrentQueue, ^{
            __weak typeof(weakSelf)strongSelf = weakSelf;
            if (strongSelf) {
                block(strongSelf, key, nil);
            }
        });
#if !OS_OBJECT_USE_OBJC
        dispatch_release(group);
#endif
    }
}

- (void)removeAllObjects:(WNCacheBlock)block {
    dispatch_group_t group = nil;
    WNMemoryCacheBlcok memoryBlock = nil;
    WNDiskCacheBlcok diskBlock = nil;
    
    if (block) {
        group = dispatch_group_create();
        dispatch_group_enter(group);
        memoryBlock = ^(WNMemoryCache *memoryCache){
            dispatch_group_leave(group);
        };
        
        dispatch_group_enter(group);
        diskBlock = ^(WNDiskCache *diskCache){
            dispatch_group_leave(group);
        };
    }
    
    [_memoryCache removeAllObjects:memoryBlock];
    [_diskCache removeAllObjects:diskBlock];
    if (group) {
        __weak typeof(self)weakSelf = self;
        dispatch_group_notify(group, _concurrentQueue, ^{
            __weak typeof(weakSelf)strongSelf = weakSelf;
            if (strongSelf) {
                block(strongSelf);
            }
        });
#if !OS_OBJECT_USE_OBJC
        dispatch_release(group);
#endif
    }
}

- (void)trimToDate:(NSDate *)date block:(WNCacheBlock)block {
    if (!date) {
        return ;
    }
    dispatch_group_t group = nil;
    WNMemoryCacheBlcok memoryBlock = nil;
    WNDiskCacheBlcok diskBlock = nil;
    
    if (block) {
        group = dispatch_group_create();
        dispatch_group_enter(group);
        memoryBlock = ^(WNMemoryCache *memoryCache){
            dispatch_group_leave(group);
        };
        
        dispatch_group_enter(group);
        diskBlock = ^(WNDiskCache *diskCache){
            dispatch_group_leave(group);
        };
    }
    
    [_memoryCache trimToDate:date block:memoryBlock];
    [_diskCache trimToDate:date block:diskBlock];
    
    if (group) {
        __weak typeof(self)weakSelf = self;
        dispatch_group_notify(group, _concurrentQueue, ^{
            __weak typeof(weakSelf)strongSelf = weakSelf;
            if (strongSelf) {
                block(strongSelf);
            }
        });
#if !OS_OBJECT_USE_OBJC
        dispatch_release(group);
#endif
    }
}

- (NSUInteger)diskByteCount {
    __block NSUInteger byteCount = 0;
    [_diskCache synchronouslyLockFileAccessWhileExecutingBlock:^(WNDiskCache * _Nullable diskCache) {
        byteCount = diskCache.byteCount;
    }];
    return byteCount;
}

- (__nullable id)objectForKey:(NSString *)key {
    if (!key) {
        return nil;
    }
    
    __block id object = nil;
    object = [_memoryCache objectForKey:key];
    if (object) {
        // 更新缓存的修改时间
        [_diskCache fileURLForKey:key block:nil];
    } else {
        object = [_diskCache objectForKey:key];
        [_memoryCache setObject:object forKey:key withCost:0];
    }
    return object;
}

- (void)setObject:(id<NSCoding>)object forKey:(NSString *)key {
    if (!key || !object) {
        return;
    }
    
    [_memoryCache setObject:object forKey:key withCost:0];
    [_diskCache setObject:object forKey:key];
}

- (id)objectForKeyedSubscript:(NSString *)key {
    return [self objectForKey:key];
}

- (void)removeObjectForKey:(NSString *)key {
    if (!key) {
        return;
    }
    [_memoryCache removeObjectForKey:key];
    [_diskCache removeObjectForKey:key];
}

- (void)trimToDate:(NSDate *)date {
    if (!date) {
        return;
    }
    [_memoryCache trimToDate:date];
    [_diskCache trimToDate:date];
}

- (void)removeAllObjects {
    [_memoryCache removeAllObjects];
    [_diskCache removeAllObjects];
}

@end
