//
//  ViewController.m
//  YYEventSource
//
//  Created by xiaotian on 2021/2/23.
//

#import "ViewController.h"
#import "EventSource.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    [self connect];
}

- (void)connect {
    NSString *url = @"";
    EventSource *eventSource = [EventSource eventSourceWithURL:[NSURL URLWithString:url]];

    [eventSource onMessage:^(Event *e) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSData *jsonData = [e.data dataUsingEncoding:NSUTF8StringEncoding];
            NSError *err;
            NSDictionary *dic = [NSJSONSerialization JSONObjectWithData:jsonData options:NSJSONReadingMutableContainers error:&err];
            NSLog(@"------------------\n%@", dic);
        });
    }];
    
    [eventSource onError:^(Event *event) {
        NSLog(@"error:%@", event.error);
    }];
}

@end
