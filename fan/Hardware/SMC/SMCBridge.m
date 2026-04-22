#import "SMCBridge.h"

#import <IOKit/IOKitLib.h>

static NSString * const FANSMCBridgeErrorDomain = @"fan.SMCBridge";
static const int FANSMCSelector = 2;
static const uint8_t FANSMCReadBytesCommand = 5;
static const uint8_t FANSMCWriteBytesCommand = 6;
static const uint8_t FANSMCReadKeyInfoCommand = 9;
static const uint8_t FANSMCSuccess = 0x00;

typedef char FANSMCBytes[32];

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    uint8_t dataAttributes;
    uint8_t reserved[3];
} FANSMCKeyInfo;

typedef struct {
    uint32_t key;
    uint8_t vers[4];
    uint8_t pLimitData[16];
    uint8_t padding0[4];
    FANSMCKeyInfo keyInfo;
    uint8_t result;
    uint8_t status;
    uint8_t data8;
    uint8_t padding1;
    uint32_t data32;
    FANSMCBytes bytes;
} FANSMCKeyData;

static uint32_t FANSMCStringToUInt32(NSString *value) {
    const char *chars = [value UTF8String];
    uint32_t result = 0;
    for (NSUInteger index = 0; index < 4; index += 1) {
        result <<= 8;
        if (index < value.length) {
            result |= (uint8_t)chars[index];
        }
    }
    return result;
}

static NSString *FANSMCUInt32ToString(uint32_t value) {
    char chars[5];
    chars[0] = (value >> 24) & 0xff;
    chars[1] = (value >> 16) & 0xff;
    chars[2] = (value >> 8) & 0xff;
    chars[3] = value & 0xff;
    chars[4] = '\0';
    return [[NSString stringWithCString:chars encoding:NSASCIIStringEncoding] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static kern_return_t FANSMCCall(io_connect_t connection, const FANSMCKeyData *input, FANSMCKeyData *output) {
    size_t inputSize = sizeof(FANSMCKeyData);
    size_t outputSize = sizeof(FANSMCKeyData);
    return IOConnectCallStructMethod(connection, FANSMCSelector, input, inputSize, output, &outputSize);
}

@interface SMCBridge ()

@property (nonatomic, assign) io_connect_t connection;
@property (nonatomic, readwrite, copy) NSString *serviceName;

@end

@implementation SMCBridge

- (nullable instancetype)initWithError:(NSError * _Nullable * _Nullable)error {
    self = [super init];
    if (!self) {
        return nil;
    }

    NSArray<NSString *> *serviceCandidates = @[ @"AppleSMC", @"AppleSMCKeysEndpoint" ];
    io_service_t service = IO_OBJECT_NULL;

    for (NSString *candidate in serviceCandidates) {
        service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching(candidate.UTF8String));
        if (service != IO_OBJECT_NULL) {
            self.serviceName = candidate;
            break;
        }
    }

    if (service == IO_OBJECT_NULL) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:FANSMCBridgeErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: @"AppleSMC service was not found"}];
        }
        return nil;
    }

    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &_connection);
    IOObjectRelease(service);

    if (result != kIOReturnSuccess) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:FANSMCBridgeErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"failed to open AppleSMC connection: 0x%08x", result]}];
        }
        return nil;
    }

    return self;
}

- (void)dealloc {
    if (_connection != IO_OBJECT_NULL) {
        IOServiceClose(_connection);
        _connection = IO_OBJECT_NULL;
    }
}

- (nullable NSDictionary<NSString *, id> *)readValueForKey:(NSString *)key error:(NSError * _Nullable * _Nullable)error {
    FANSMCKeyData input = {0};
    FANSMCKeyData output = {0};
    input.key = FANSMCStringToUInt32(key);
    input.data8 = FANSMCReadKeyInfoCommand;

    kern_return_t result = FANSMCCall(self.connection, &input, &output);
    if (result != kIOReturnSuccess || output.result != FANSMCSuccess) {
        if (error != NULL) {
            NSString *message = result == kIOReturnSuccess
                ? [NSString stringWithFormat:@"failed to read key info for %@: smc result 0x%02x", key, output.result]
                : [NSString stringWithFormat:@"failed to read key info for %@: 0x%08x", key, result];
            *error = [NSError errorWithDomain:FANSMCBridgeErrorDomain code:3 userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return nil;
    }

    input.keyInfo = output.keyInfo;
    input.data8 = FANSMCReadBytesCommand;
    result = FANSMCCall(self.connection, &input, &output);
    if (result != kIOReturnSuccess || output.result != FANSMCSuccess) {
        if (error != NULL) {
            NSString *message = result == kIOReturnSuccess
                ? [NSString stringWithFormat:@"failed to read bytes for %@: smc result 0x%02x", key, output.result]
                : [NSString stringWithFormat:@"failed to read bytes for %@: 0x%08x", key, result];
            *error = [NSError errorWithDomain:FANSMCBridgeErrorDomain code:4 userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return nil;
    }

    NSData *data = [NSData dataWithBytes:output.bytes length:output.keyInfo.dataSize];
    return @{
        @"key": key,
        @"dataType": FANSMCUInt32ToString(output.keyInfo.dataType),
        @"dataSize": @(output.keyInfo.dataSize),
        @"bytes": data,
    };
}

- (BOOL)writeValueForKey:(NSString *)key bytes:(NSData *)bytes dataType:(NSString *)dataType error:(NSError * _Nullable * _Nullable)error {
    FANSMCKeyData input = {0};
    FANSMCKeyData output = {0};

    input.key = FANSMCStringToUInt32(key);
    input.data8 = FANSMCReadKeyInfoCommand;
    kern_return_t result = FANSMCCall(self.connection, &input, &output);
    if (result != kIOReturnSuccess || output.result != FANSMCSuccess) {
        if (error != NULL) {
            NSString *message = result == kIOReturnSuccess
                ? [NSString stringWithFormat:@"failed to read key info before writing %@: smc result 0x%02x", key, output.result]
                : [NSString stringWithFormat:@"failed to read key info before writing %@: 0x%08x", key, result];
            *error = [NSError errorWithDomain:FANSMCBridgeErrorDomain code:5 userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return NO;
    }

    input.keyInfo = output.keyInfo;
    input.keyInfo.dataType = FANSMCStringToUInt32(dataType);
    input.keyInfo.dataSize = (uint32_t)MIN(bytes.length, sizeof(FANSMCBytes));
    input.data8 = FANSMCWriteBytesCommand;
    memset(input.bytes, 0, sizeof(FANSMCBytes));
    memcpy(input.bytes, bytes.bytes, input.keyInfo.dataSize);

    result = FANSMCCall(self.connection, &input, &output);
    if (result != kIOReturnSuccess || output.result != FANSMCSuccess) {
        if (error != NULL) {
            NSString *message = result == kIOReturnSuccess
                ? [NSString stringWithFormat:@"failed to write key %@: smc result 0x%02x", key, output.result]
                : [NSString stringWithFormat:@"failed to write key %@: 0x%08x", key, result];
            *error = [NSError errorWithDomain:FANSMCBridgeErrorDomain code:6 userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return NO;
    }

    return YES;
}

@end
