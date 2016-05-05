//
//  ViewController.m
//  WannaCache
//
//  Created by X-Liang on 16/4/27.
//  Copyright © 2016年 X-Liang. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSArray *array = @[@(2),@(3),@(5),@(6),@(8)];
    NSUInteger index = [self beiarySearch:array];
    
    NSIndexSet *sets = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(index, array.count - index)];
    [array enumerateObjectsAtIndexes:sets
                             options:NSEnumerationConcurrent usingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
                                 NSLog(@"%@",obj);
                             }];
}

#define Target 5

- (NSUInteger)beiarySearch:(NSArray *)array {
    NSUInteger begin = 0, end = array.count - 1;
    while (begin <= end) {
        NSUInteger mid = (begin + end) * .5f;
        if ([array[mid] integerValue] >= Target ) {
            end = mid - 1;
        } else if ([array[mid] integerValue] < Target) {
            begin = mid + 1;
        }
        
    }
    return begin;
}

@end
