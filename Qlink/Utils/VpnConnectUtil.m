//
//  VpnConnectUtil.m
//  Qlink
//
//  Created by Jelly Foo on 2018/7/10.
//  Copyright © 2018年 pan. All rights reserved.
//

#import "VpnConnectUtil.h"
#import "VPNOperationUtil.h"
#import "Qlink-Swift.h"
#import "TransferUtil.h"
#import "ToxRequestModel.h"
#import "P2pMessageManage.h"
#import "VPNFileUtil.h"
#import "VPNMode.h"

#define KEYWINDOW [UIApplication sharedApplication].keyWindow

@interface VpnConnectUtil () {
    BOOL checkConnnectOK;
    BOOL connectVpnOK;
}

@property (nonatomic, strong) VPNInfo *vpnInfo;
@property (nonatomic, strong) NSData *vpnData;

@end

@implementation VpnConnectUtil

- (instancetype)initWithVpn:(VPNInfo *)vpnInfo {
    if (self = [super init]) {
        _vpnInfo = vpnInfo;
        [self addObserve];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Observe
- (void)addObserve {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(vpnStatusChange:) name:VPN_STATUS_CHANGE_NOTI object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(receiveVPNFile:) name:RECEIVE_VPN_FILE_NOTI object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(savePreferenceFail:) name:SAVE_VPN_PREFERENCE_FAIL_NOTI object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(checkConnectRsp:) name:CHECK_CONNECT_RSP_NOTI object:nil];
    
}

#pragma mark - Noti
- (void)vpnStatusChange:(NSNotification *)noti {
    NEVPNStatus status = (NEVPNStatus)[noti.object integerValue];
    switch (status) {
        case NEVPNStatusInvalid:
            break;
        case NEVPNStatusDisconnected:
        {
            [AppD.window hideHud];
        }
            break;
        case NEVPNStatusConnecting:
            break;
        case NEVPNStatusConnected:
        {
            connectVpnOK = YES;
            [AppD.window hideHud];
//            [self jumpToVPNConnected];
        }
            break;
        case NEVPNStatusReasserting:
            break;
        case NEVPNStatusDisconnecting:
        {
        }
            break;
        default:
            break;
    }
}

- (void)receiveVPNFile:(NSNotification *)noti {
    _vpnData = noti.object;
    [self startConnectVPN];
}

- (void)startConnectVPN {
    // vpn连接操作
    [VPNOperationUtil shareInstance].operationType = normalConnect;
    [VPNUtil.shareInstance configVPNWithVpnData:_vpnData];
}

- (void)savePreferenceFail:(NSNotification *)noti {
    [AppD.window hideHud];
    [AppD.window showHint:NSStringLocalizable(@"save_failed")];
}

- (void)checkConnectRsp:(NSNotification *)noti {
    checkConnnectOK = YES;
    [AppD.window hideHud];
    
    [self connectAction];
}

#pragma mark - Operation
- (void)checkConnect {
    if (![self vpnIsMine]) { // 连接别人的vpn
        [self addSendCheckConnect];
    } else { // 连接自己的vpn
        checkConnnectOK = YES;
        
        [self connectAction];
    }
}

- (BOOL)vpnIsMine {
    NSString *myP2pId = [ToxManage getOwnP2PId];
    return [_vpnInfo.p2pId isEqualToString:myP2pId]?YES:NO;
}

- (void)addSendCheckConnect {
    NSTimeInterval timeout = 15;
    [AppD.window showHudInView:KEYWINDOW hint:NSStringLocalizable(@"checking")];
    checkConnnectOK = NO;
    // 发送获取配置文件消息
    ToxRequestModel *model = [[ToxRequestModel alloc] init];
    model.type = checkConnectReq;
    NSString *p2pid = [ToxManage getOwnP2PId];
    NSDictionary *dataDic = @{@"appVersion":APP_Build,@"p2pId":p2pid};
    model.data = dataDic.mj_JSONString;
    NSString *str = model.mj_JSONString;
    [ToxManage sendMessageWithMessage:str withP2pid:_vpnInfo.p2pId];
    [self performSelector:@selector(checkConnectTimeout) withObject:nil afterDelay:timeout];
}

- (void)checkConnectTimeout {
    if (!checkConnnectOK) {
        [AppD.window hideHud];
        [AppD.window showHint:NSStringLocalizable(@"connect_timeout")];
        [[NSNotificationCenter defaultCenter] postNotificationName:Check_Connect_Timeout_Noti object:nil];
    }
}

- (void)connectVpnTimeout {
    if (!connectVpnOK) {
        [VPNUtil.shareInstance stopVPN];
        [AppD.window hideHud];
        [KEYWINDOW showHint:NSStringLocalizable(@"vpn_timeout")];
        [[NSNotificationCenter defaultCenter] postNotificationName:Connect_Vpn_Timeout_Noti object:nil];
    }
}

#pragma mark - Action
- (void)connectAction {
    if (_vpnInfo.profileLocalPath.length <= 0) {
        [AppD.window showHint:NSStringLocalizable(@"profile_empty")];
        DDLogDebug(@"没有profileLocalPath,无法连接vpn");
        return;
    }
    
    if (![TransferUtil isConnectionAssetsAllowedWithCost:_vpnInfo.cost]) {
        [AppD.window showView:KEYWINDOW hint:NSStringLocalizable(@"insufficient_assets")];
        return;
    }
    
    if (!checkConnnectOK) {
        return;
    }
    
    connectVpnOK = NO;
    
    NSTimeInterval timeout = CONNECT_VPN_TIMEOUT;
    [AppD.window showHudInView:AppD.window hint:NSStringLocalizable(@"connecting")];
    
    [self performSelector:@selector(connectVpnTimeout) withObject:nil afterDelay:timeout];
    
    if ([self vpnIsMine]) { // 连自己
        NSString *fileName = [[_vpnInfo.profileLocalPath componentsSeparatedByString:@"/"] lastObject];
        NSString *vpnPath = [VPNFileUtil getVPNPathWithFileName:fileName];
        _vpnData = [NSData dataWithContentsOfFile:vpnPath];
        [self startConnectVPN];
        return;
    }
    
    // 给c层传文件名
    ToxManage.shareMange.vpnSourceName = _vpnInfo.profileLocalPath;
    // 开始连接vpn
    if (_vpnData) { // 如果配置文件data已存在
        [self startConnectVPN];
    } else {
        // 发送获取配置文件消息
        ToxRequestModel *model = [[ToxRequestModel alloc] init];
        model.type = sendVpnFileRequest;
        NSString *p2pid = [ToxManage getOwnP2PId];
        NSDictionary *dataDic = @{@"appVersion":APP_Build,@"vpnName":_vpnInfo.vpnName,@"filePath":_vpnInfo.profileLocalPath,@"p2pId":p2pid};
        model.data = dataDic.mj_JSONString;
        NSString *str = model.mj_JSONString;
        
        [ToxManage sendMessageWithMessage:str withP2pid:_vpnInfo.p2pId];
    }
}

@end
