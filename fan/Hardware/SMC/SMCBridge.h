#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SMCBridge : NSObject

@property (nonatomic, readonly, copy) NSString *serviceName;

- (nullable instancetype)initWithError:(NSError * _Nullable * _Nullable)error;
- (nullable NSDictionary<NSString *, id> *)readValueForKey:(NSString *)key error:(NSError * _Nullable * _Nullable)error;
- (BOOL)writeValueForKey:(NSString *)key bytes:(NSData *)bytes dataType:(NSString *)dataType error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
