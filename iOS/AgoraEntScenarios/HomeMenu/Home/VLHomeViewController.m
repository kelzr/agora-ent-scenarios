//
//  VLHomeViewController.m
//  VoiceOnLine
//

#import "VLHomeViewController.h"
#import "VLHomeView.h"
#import "VLOnLineListVC.h"
#import "VLMacroDefine.h"
#import "MenuUtils.h"
#import "KTVMacro.h"

@interface VLHomeViewController ()<VLHomeViewDelegate>

@end

@implementation VLHomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self setBackgroundImage:@"home_bg_image"];
    [self setNaviTitleName:AGLocalizedString(@"声网")];
    
    [self setUpUI];
}

- (void)setUpUI {
    VLHomeView *homeView = [[VLHomeView alloc]initWithFrame:CGRectMake(0, 0, SCREEN_WIDTH, SCREEN_HEIGHT-kBottomTabBarHeight) withDelegate:self];
    [self.view addSubview:homeView];
    
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
//    self.hidesBottomBarWhenPushed = YES;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
//    self.hidesBottomBarWhenPushed = NO;
}


#pragma mark - Public Methods
- (void)configNavigationBar:(UINavigationBar *)navigationBar {
    [super configNavigationBar:navigationBar];
}
- (BOOL)preferredNavigationBarHidden {
    return true;
}


- (void)itemClickAction:(int)tagValue {
    NSArray* sceneNames = @[@"VoiceChat", @"KTV", @"LiveShow", @"SA"];
    [[NetworkManager shared] reportSceneClickWithSceneName:sceneNames[tagValue]];
    switch (tagValue) {
        case 0: {
            VRRoomsViewController *vc = [[VRRoomsViewController alloc] initWithUser:VLUserCenter.user];
            vc.hidesBottomBarWhenPushed = YES;
            [self.navigationController pushViewController:vc animated:YES];
        }
            break;
        case 1: {
            VLOnLineListVC *vc = [[VLOnLineListVC alloc]init];
            [self.navigationController pushViewController:vc animated:YES];
        } break;
        case 2: {
            ShowRoomListVC *vc = [ShowRoomListVC new];
            [self.navigationController pushViewController:vc animated:YES];
        } break;
        case 3: {
            SARoomsViewController *roomVc = [[SARoomsViewController alloc] initWithUser:VLUserCenter.user];
            roomVc.hidesBottomBarWhenPushed = YES;
            [self.navigationController pushViewController:roomVc animated:YES];
        } break;
        default:
            break;
    }
}

@end
