//
//  Action.m
//  article
//
//  Created by EasyIOS on 14-4-8.
//  Copyright (c) 2014年 zhuchao. All rights reserved.
//

#import "Action.h"
#import <ReactiveObjC/ReactiveObjC.h>

@interface Action()
@property(nonatomic,assign)BOOL cacheEnable;
@property(nonatomic,assign)BOOL dataFromCache;

@property(nonatomic,retain)NSString *DEFAULT_SCHEME;//http/https/ftp协议
@property(nonatomic,retain)NSString *HOST_URL;//服务端域名:端口
@property(nonatomic,retain)NSString *CLIENT;//自定义客户端识别
@property(nonatomic,retain)NSString *CODE_KEY;//错误码key,支持路径 如 data/code
@property(nonatomic,assign)NSUInteger RIGHT_CODE;//正确校验码
@property(nonatomic,retain)NSString *MSG_KEY;//消息提示msg,支持路径 如 data/msg
@end
@implementation Action

DEF_SINGLETON(Action)

+(void)actionConfigScheme:(NSString *)scheme
                     host:(NSString *)host
                 client:(NSString *)client
                codeKey:(NSString *)codeKey
              rightCode:(NSInteger)rightCode
                 msgKey:(NSString *)msgKey{
    [Action sharedInstance].DEFAULT_SCHEME = scheme;
    [Action sharedInstance].HOST_URL = host;
    [Action sharedInstance].CLIENT = client;
    [Action sharedInstance].CODE_KEY = codeKey;
    [Action sharedInstance].RIGHT_CODE = rightCode;
    [Action sharedInstance].MSG_KEY = msgKey;
}

+(void)actionConfigHost:(NSString *)host client:(NSString *)client codeKey:(NSString *)codeKey rightCode:(NSInteger)rightCode msgKey:(NSString *)msgKey{
    [Action actionConfigScheme:@"http" host:host client:client codeKey:codeKey rightCode:rightCode msgKey:msgKey];
}

+(id)Action{
    return [[[self class] alloc] init];
}
- (id)init
{
    self = [super init];
    if(self){
        _cacheEnable = NO;
        _dataFromCache = NO;
    }
    return self;
}

- (id)initWithCache
{
    self = [self init];
    _cacheEnable = YES;
    return self;
}

-(void)useCache{
    _cacheEnable = YES;
}

-(void)readFromCache{
    _dataFromCache = YES;
}
-(void)notReadFromCache{
    _dataFromCache = NO;
}

-(NSURLSessionDownloadTask *)Download:(Request *)msg{

    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    AFURLSessionManager *manager = [[AFURLSessionManager alloc] initWithSessionConfiguration:configuration];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:msg.downloadUrl]];
    if (msg.timeoutInterval != 0) {
        request.timeoutInterval = msg.timeoutInterval;
    }
    if ([Action sharedInstance].CLIENT.isNotEmpty) {
       [request setValue:[Action sharedInstance].CLIENT forHTTPHeaderField:@"User-Agent"];
    }
    if(msg.httpHeaderFields.isNotEmpty){
        [msg.httpHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
            [request setValue:value forHTTPHeaderField:key];
        }];
    }
    [self sending:msg];
    @weakify(msg,self);

    NSURLSessionDownloadTask *op = [manager downloadTaskWithRequest:request progress:^(NSProgress * downloadProgress) {
        @strongify(msg,self);
        msg.progress = downloadProgress;
        [self progressing:msg];
    } destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) {
        NSURL *documentsDirectoryURL = [NSURL URLWithString:msg.targetPath];
        return [documentsDirectoryURL URLByAppendingPathComponent:[response suggestedFilename]];
    } completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
        @strongify(msg,self);
        msg.error = error;
        [self failed:msg];
    }];

    msg.url = op.currentRequest.URL;
    msg.op = op;

    [op resume];
    return op;
}


-(NSURLSessionDataTask *) Send:(Request *)msg
{
    NSString *url = @"";
    NSDictionary *requestParams = nil;
    if(msg.STATICPATH.isNotEmpty){
        url = msg.STATICPATH;
    }else{
        url = [NSString stringWithFormat:@"%@://%@%@",
               msg.SCHEME.isNotEmpty?msg.SCHEME:[Action sharedInstance].DEFAULT_SCHEME,
               msg.HOST.isNotEmpty?msg.HOST:[Action sharedInstance].HOST_URL,
               msg.PATH];
    }
    if(msg.appendPathInfo.isNotEmpty){
        url = [url stringByAppendingString:msg.appendPathInfo];
    }else{
        requestParams = msg.requestParams;
    }

    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    AFURLSessionManager *manager = [[AFURLSessionManager alloc] initWithSessionConfiguration:configuration];

    NSMutableURLRequest *request = [[AFHTTPRequestSerializer serializer] requestWithMethod:msg.METHOD URLString:url parameters:requestParams error:nil];

    if ([Action sharedInstance].CLIENT.isNotEmpty) {
       [request setValue:[Action sharedInstance].CLIENT forHTTPHeaderField:@"User-Agent"];
    }

    if(msg.httpHeaderFields.isNotEmpty){
        [msg.httpHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
            [request setValue:value forHTTPHeaderField:key];
        }];
    }
    if (msg.timeoutInterval != 0) {
        request.timeoutInterval = msg.timeoutInterval;
    }
    //设置后台返回数据可接收类型
    AFJSONResponseSerializer *respond = [AFJSONResponseSerializer serializer];
    respond.acceptableContentTypes = msg.acceptableContentTypes;
    manager.responseSerializer = respond;

    [self sending:msg];
    @weakify(msg,self);
    NSURLSessionDataTask *op = [manager dataTaskWithRequest:request uploadProgress:^(NSProgress * _Nonnull uploadProgress) {
        
    } downloadProgress:^(NSProgress * _Nonnull downloadProgress) {
        
    } completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
        if(error == nil){
            if ([responseObject isKindOfClass:[NSArray class]]) {
                NSDictionary *responseDict = @{
                    @"isSuccess": @"1",
                    @"data": responseObject
                };
                responseObject = responseDict;
                msg.needCheckCode = NO;
            } else {
                msg.needCheckCode = YES;
            }
            msg.output = responseObject;
            @strongify(msg,self);
            
            [self checkCode:msg];
            
        }else{
            @strongify(msg,self);
            msg.error = error;
            [self failed:msg];
            
        }
    }];

    msg.url = op.currentRequest.URL;
    msg.op = op;
    
    [op resume];
    return op;
}

-(NSURLSessionDataTask *)Upload:(Request *)msg{
    NSString *url = @"";
    NSDictionary *requestParams = nil;
    if(msg.STATICPATH.isNotEmpty){
        url = msg.STATICPATH;
    }else{
        url = [NSString stringWithFormat:@"%@://%@%@",
               msg.SCHEME.isNotEmpty?msg.SCHEME:[Action sharedInstance].DEFAULT_SCHEME,
               msg.HOST.isNotEmpty?msg.HOST:[Action sharedInstance].HOST_URL,
               msg.PATH];
    }
    if(msg.appendPathInfo.isNotEmpty){
        url = [url stringByAppendingString:msg.appendPathInfo];
    }else{
        requestParams = msg.requestParams;
    }

    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    AFURLSessionManager *manager = [[AFURLSessionManager alloc] initWithSessionConfiguration:configuration];
    manager.responseSerializer = [AFJSONResponseSerializer serializer];
    [self sending:msg];
    NSDictionary *file = msg.requestFiles;
    NSMutableURLRequest *request = [[AFHTTPRequestSerializer serializer] multipartFormRequestWithMethod:@"POST" URLString:url parameters:requestParams constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
        [file enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
            if([obj isKindOfClass:[NSURL class]]){
                [formData appendPartWithFileURL:obj name:key error:nil];
            }else if([obj isKindOfClass:[NSData class]]){
                [formData appendPartWithFormData:obj name:key];
            }else if([obj isKindOfClass:[NSString class]]){
                [formData appendPartWithFileURL:[NSURL fileURLWithPath:obj] name:key error:nil];
            }
        }];
    } error:nil];

    if ([Action sharedInstance].CLIENT.isNotEmpty) {
       [request setValue:[Action sharedInstance].CLIENT forHTTPHeaderField:@"User-Agent"];
    }
    if(msg.httpHeaderFields.isNotEmpty){
        [msg.httpHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
            [request setValue:value forHTTPHeaderField:key];
        }];
    }
    if (msg.timeoutInterval != 0) {
        request.timeoutInterval = msg.timeoutInterval;
    }

    @weakify(msg,self);
    NSURLSessionDataTask *op = [manager uploadTaskWithStreamedRequest:request progress:^(NSProgress * uploadProgress) {
        msg.progress = uploadProgress;
        [self progressing:msg];
    } completionHandler:^(NSURLResponse * response, NSDictionary*responseObject, NSError * error) {
        @strongify(msg,self);
        if (error == nil) {
            msg.output = responseObject;
            [self checkCode:msg];
        }else{
            msg.error = error;
            [self failed:msg];
        }
    }];

    msg.url = op.currentRequest.URL;
    msg.op = op;

    [op resume];
    return op;
}

-(void)checkCode:(Request *)msg{
    if([self doCheckCode:msg]){
        [self success:msg];
    }else{
        [self error:msg];
    }
}

-(BOOL)doCheckCode:(Request *)msg{
    if (msg.needCheckCode) {
        msg.codeKey = [msg.output objectAtPath:[Action sharedInstance].CODE_KEY];
        if([msg.output objectAtPath:[Action sharedInstance].CODE_KEY] && [[msg.output objectAtPath:[Action sharedInstance].CODE_KEY] intValue] == [Action sharedInstance].RIGHT_CODE){
            return true;
        }else{
            return false;
        }
    }else{
        return true;
    }
}

-(void)sending:(Request *)msg{
    msg.state = RequestStateSending;
    if([self.aDelegaete respondsToSelector:@selector(handleActionMsg:)]){
        [self.aDelegaete handleActionMsg:msg];
    }
}

- (void)success:(Request *)msg{
    msg.message = [msg.output objectAtPath:[Action sharedInstance].MSG_KEY]?:@"";
    msg.state = RequestStateSuccess;
    if([self.aDelegaete respondsToSelector:@selector(handleActionMsg:)]){
        [self.aDelegaete handleActionMsg:msg];
    }
}


- (void)failed:(Request *)msg{
    if(msg.error.userInfo!= nil && [msg.error.userInfo objectForKey:@"NSLocalizedDescription"]){
        msg.message = [msg.error.userInfo objectForKey:@"NSLocalizedDescription"];
    }
    msg.state = RequestStateFailed;
    if (msg.error.code == -1001) {
        msg.isTimeout = YES;
    }
    NSLog(@"Failed:%@",msg.error);
    if([self.aDelegaete respondsToSelector:@selector(handleActionMsg:)]){
        [self.aDelegaete handleActionMsg:msg];
    }
}

- (void)error:(Request *)msg{
    if([msg.output objectAtPath:[Action sharedInstance].MSG_KEY]){
        msg.message = [msg.output objectAtPath:[Action sharedInstance].MSG_KEY];
        NSLog(@"Error:%@",msg.message);
    }
    msg.state = RequestStateError;
    if([self.aDelegaete respondsToSelector:@selector(handleActionMsg:)]){
        [self.aDelegaete handleActionMsg:msg];
    }
}

-(void)progressing:(Request *)msg{
    if([self.aDelegaete respondsToSelector:@selector(handleProgressMsg:)]){
        [self.aDelegaete handleProgressMsg:msg];
    }
}

@end
