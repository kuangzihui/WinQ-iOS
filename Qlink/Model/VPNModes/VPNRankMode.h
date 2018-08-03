//
//  VPNRankMode.h
//  Qlink
//
//  Created by 旷自辉 on 2018/8/2.
//  Copyright © 2018年 pan. All rights reserved.
//

#import "BBaseModel.h"

@interface VPNRankMode : BBaseModel
@property (nonatomic , strong) NSString *assetName;
@property (nonatomic , assign) NSInteger connectSuccessNum;
@property (nonatomic , assign) CGFloat rewardTotal;
@property (nonatomic , strong) NSString *imgUrl;
@end