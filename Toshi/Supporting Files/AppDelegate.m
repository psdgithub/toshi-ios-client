
#import "AppDelegate.h"

#import "Toshi-Swift.h"

#import "NSData+ows_StripToken.h"
#import "EmptyCallHandler.h"

#import <EtherealCereal/EtherealCereal.h>

#import <SignalServiceKit/OWSSignalService.h>
#import <SignalServiceKit/TSOutgoingMessage.h>
#import <SignalServiceKit/TSStorageManager.h>
#import <SignalServiceKit/TSStorageManager+keyingMaterial.h>
#import <SignalServiceKit/OWSSyncContactsMessage.h>
#import <SignalServiceKit/NSDate+millisecondTimeStamp.h>
#import <SignalServiceKit/TextSecureKitEnv.h>
#import <SignalServiceKit/OWSIncomingMessageReadObserver.h>
#import <SignalServiceKit/TSSocketManager.h>
#import <SignalServiceKit/OWSDispatch.h>
#import <SignalServiceKit/TSPreferences.h>

#import <AxolotlKit/SessionCipher.h>
#import "Common.h"

#import <Fabric/Fabric.h>
#import <Crashlytics/Crashlytics.h>

NSString *const LaunchedBefore = @"LaunchedBefore";
NSString *const RequiresSignIn = @"RequiresSignIn";

@import WebRTC;

@interface AppDelegate () <TSPreferences>

@property (nonatomic) OWSIncomingMessageReadObserver *incomingMessageReadObserver;

@property (nonatomic) OWSMessageFetcherJob *messageFetcherJob;

@property (nonatomic) UIWindow *screenProtectionWindow;

@property (nonatomic, copy, readwrite) NSString *token;
@property (nonatomic) NSString *voipToken;

@end

@implementation AppDelegate
@synthesize token = _token;
@synthesize voipToken = _voipToken;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    NSString *tokenChatServiceBaseURL = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"TokenChatServiceBaseURL"];
    [OWSSignalService setBaseURLPath:tokenChatServiceBaseURL];

    // Set the seed the generator for rand().
    //
    // We should always use arc4random() instead of rand(), but we
    // still want to ensure that any third-party code that uses rand()
    // gets random values.
    srand((unsigned int)time(NULL));
    [self verifyDBKeysAvailableBeforeBackgroundLaunch];

    [Fabric with:@[[Crashlytics class]]];
    
    [self setupBasicAppearance];

    if ([Yap isCurrentUserDataAccessible]) {

        [TokenUser retrieveCurrentUser];

        [self setupDB];
    }

    [self configureAndPresentWindow];

    return YES;
}

+ (NSString *)documentsPath
{
    static NSString *path = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
                  {
                      if (iosMajorVersion() >= 8)
                      {
                          NSString *groupName = [@"group." stringByAppendingString:[[NSBundle mainBundle] bundleIdentifier]];
                          
                          NSURL *groupURL = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:groupName];
                          if (groupURL != nil)
                          {
                              NSString *documentsPath = [[groupURL path] stringByAppendingPathComponent:@"Documents"];
                              
                              [[NSFileManager defaultManager] createDirectoryAtPath:documentsPath withIntermediateDirectories:true attributes:nil error:NULL];
                              
                              path = documentsPath;
                          }
                          else
                              path = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true)[0];
                      }
                      else
                          path = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, true)[0];
                  });
    
    return path;
}

- (void)configureAndPresentWindow {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [Theme viewBackgroundColor];
    self.window.rootViewController = [[TabBarController alloc] init];

    [self.window makeKeyAndVisible];

    if ([Yap isCurrentUserDataAccessible] == false) {
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:[NSString addressChangeAlertShown]]; //suppress alert for users created >=v1.1.2
        [[NSUserDefaults standardUserDefaults] synchronize];

        [self presentSplash];
    }
}

- (void)showNetworkAlertIfNeeded {
    // To drive this point really home we could show this for every launch instead.
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DidShowMoneyAlert"]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Be aware!" message:@"Toshi is running on Testnet. Do not send Ethereum from Mainnet." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Continue" style:UIAlertActionStyleDefault handler:nil]];

        [self.window.rootViewController presentViewController:alert animated:YES completion:^{
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"DidShowMoneyAlert"];
        }];
    }
}

- (void)signOutUser
{
    [TSAccountManager unregisterTextSecureWithSuccess:^{

        [[NSNotificationCenter defaultCenter] postNotificationName:@"UserDidSignOut" object:nil];
        [AvatarManager.shared cleanCache];

        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:[[NSBundle mainBundle] bundleIdentifier]];
        [[EthereumAPIClient shared] deregisterFromMainNetworkPushNotifications];
        [[TSStorageManager sharedManager] resetSignalStorage];
        [[Yap sharedInstance] wipeStorage];
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:RequiresSignIn];
        [[NSUserDefaults standardUserDefaults] synchronize];

        [[UIApplication sharedApplication] setApplicationIconBadgeNumber:0];

         exit(0);
    } failure:^(NSError *error) {
        UIAlertController *alert = [UIAlertController dismissableAlertWithTitle:@"Could not sign out" message:@"Error attempting to unregister from chat service. Our engineers are looking into it."];

        [Navigator presentModally:alert];
    }];
}

- (void)createNewUser
{
    __weak typeof(self)weakSelf = self;
    [[IDAPIClient shared] registerUserIfNeeded:^{
        typeof(self)strongSelf = weakSelf;

        [[ChatAPIClient shared] registerUser];

        [strongSelf didCreateUser];
        [strongSelf setupDB];
    }];
}

- (void)signInUser
{
    [self showNetworkAlertIfNeeded];
    [self setupDB];
}

- (void)setupDB
{
    [self setupTSKitEnv];
    [self setupSignalService];

    [[NSNotificationCenter defaultCenter] postNotificationName:@"ChatDatabaseCreated" object:nil];
}

- (void)didCreateUser {
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:RequiresSignIn];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    [Navigator presentAddressChangeAlertIfNeeded];
}

- (void)presentSplash
{
    SplashNavigationController *splashNavigationController = [[SplashNavigationController alloc] init];
    [self.window.rootViewController presentViewController:splashNavigationController animated:NO completion:nil];
}

- (void)setupBasicAppearance {
    NSDictionary *attributtes = @{NSForegroundColorAttributeName: [Theme navigationTitleTextColor], NSFontAttributeName: [Theme boldWithSize:17]};

    UINavigationBar *navBarAppearance = [UINavigationBar appearance];
    [navBarAppearance setTitleTextAttributes:attributtes];
    [navBarAppearance setTintColor:[Theme tintColor]];
    [navBarAppearance setBarTintColor:[Theme navigationBarColor]];

    attributtes = @{NSForegroundColorAttributeName: [Theme tintColor], NSFontAttributeName: [Theme regularWithSize:17]};
    UIBarButtonItem *barButtonAppearance = [UIBarButtonItem appearanceWhenContainedInInstancesOfClasses:@[[UINavigationBar class]]];
    [barButtonAppearance setTitleTextAttributes:attributtes forState:UIControlStateNormal];
}

- (void)setupSignalService {
    // Encryption/Descryption mutates session state and must be synchronized on a serial queue.
    [SessionCipher setSessionCipherDispatchQueue:[OWSDispatch sessionStoreQueue]];

    NSLog(@"Cereal registeres phone number: %@", [Cereal shared].address);

    [[TSStorageManager sharedManager] storePhoneNumber:[[Cereal shared] address]];

    __weak typeof(self)weakSelf = self;
    [[TSAccountManager sharedInstance] ifRegistered:YES runAsync:^{

        [TSSocketManager requestSocketOpen];
        RTCInitializeSSL();

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{

            typeof(self)strongSelf = weakSelf;
            [strongSelf registerForRemoteNotifications];
        });
    }];
}

- (BOOL)isFirstLaunch
{
    return  [[NSUserDefaults standardUserDefaults] boolForKey:LaunchedBefore] == NO;
}

- (void)setupTSKitEnv {
    NSLog(@"Setting up Signal KIT environment");

    // ensure this is called from main queue for the first time
    // otherwise app crashes, because of some code path differences between
    // us and Signal app.
    [OWSSignalService sharedInstance];

    self.networkManager = [TSNetworkManager sharedManager];
    self.contactsManager = [[ContactsManager alloc] init];
    
    self.contactsUpdater = [ContactsUpdater sharedUpdater];

    TSStorageManager *storageManager = [TSStorageManager sharedManager];
    [storageManager setupForAccountName:TokenUser.current.address isFirstLaunch:[self isFirstLaunch]];

    self.messageSender = [[OWSMessageSender alloc] initWithNetworkManager:self.networkManager storageManager:storageManager contactsManager:self.contactsManager contactsUpdater:self.contactsUpdater];

    TextSecureKitEnv *sharedEnv = [[TextSecureKitEnv alloc] initWithCallMessageHandler:[[EmptyCallHandler alloc] init] contactsManager:self.contactsManager messageSender:self.messageSender notificationsManager:[[SignalNotificationManager alloc] init] preferences:self];

    [TextSecureKitEnv setSharedEnv:sharedEnv];

    self.incomingMessageReadObserver = [[OWSIncomingMessageReadObserver alloc] initWithStorageManager:storageManager messageSender:self.messageSender];
    [self.incomingMessageReadObserver startObserving];

    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:LaunchedBefore];
}

- (BOOL)isSendingIdentityApprovalRequired
{
    return NO;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    if ([TSAccountManager isRegistered]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self activateScreenProtection];
            // [TSSocketManager resignActivity];
        });
    }
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    if (Yap.isCurrentUserDataAccessible == false) {
        return;
    }

    [[TSAccountManager sharedInstance] ifRegistered:YES runAsync:^{
        // We're double checking that the app is active, to be sure since we
        // can't verify in production env due to code
        // signing.
        [TSSocketManager requestSocketOpen];
    }];

    // Send screen protection deactivation to the same queue as when resigning
    // to avoid some weird UIKit issue where app is going inactive during the launch process
    // and back to active again. Due to the queue difference, some racing conditions may apply
    // leaving the app with a protection screen when it shouldn't have any.
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self deactivateScreenProtection];
    });

    [TSPreKeyManager checkPreKeysIfNecessary];
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

- (void)activateScreenProtection {
    
    if (self.screenProtectionWindow == nil) {
        UIWindow *window = [[UIWindow alloc] init];
        window.hidden = YES;
        window.backgroundColor = [UIColor clearColor];
        window.userInteractionEnabled = NO;
        window.windowLevel = CGFLOAT_MAX;
        window.alpha = 0;

        UIVisualEffectView *effectView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleExtraLight]];
        [window addSubview:effectView];

        [effectView setTranslatesAutoresizingMaskIntoConstraints:NO];
        [[effectView.topAnchor constraintEqualToAnchor:window.topAnchor] setActive:YES];
        [[effectView.leftAnchor constraintEqualToAnchor:window.leftAnchor] setActive:YES];
        [[effectView.bottomAnchor constraintEqualToAnchor:window.bottomAnchor] setActive:YES];
        [[effectView.rightAnchor constraintEqualToAnchor:window.rightAnchor] setActive:YES];
        
        self.screenProtectionWindow = window;
    }
    
    [UIView animateWithDuration:0.3 animations:^{
        self.screenProtectionWindow.alpha = 1;
    }];

    self.screenProtectionWindow.hidden = NO;
}

- (void)deactivateScreenProtection
{
    [UIView animateWithDuration:0.3 animations:^{
        self.screenProtectionWindow.alpha = 0;
    } completion:^(BOOL finished) {
        self.screenProtectionWindow.hidden = YES;
    }];
}

- (void)verifyDBKeysAvailableBeforeBackgroundLaunch {
    if (UIApplication.sharedApplication.applicationState != UIApplicationStateBackground) {
        return;
    }

    if (![TSStorageManager isDatabasePasswordAccessible]) {
        exit(0);
    }
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    if ([url.scheme isEqualToString:@"toshi"]) {
        TabBarController *controller = (TabBarController *)self.window.rootViewController;
        [controller openDeepLinkURL:url];

        return YES;
    }

    return NO;
}

#pragma mark - Accessors

- (NSString *)token {
    if (!_token) {
        _token = @"";
    }

    return _token;
}

- (NSString *)voipToken {
    if (!_voipToken) {
        _voipToken = @"";
    }

    return _voipToken;
}

- (void)setToken:(NSString *)token {
    _token = token;

    [self updateRemoteNotificationCredentials];
}

- (void)setVoipToken:(NSString *)voipToken {
    _voipToken = voipToken;

    [self updateRemoteNotificationCredentials];
}

#pragma mark - Push notifications

- (void)registerForRemoteNotifications {
    UNAuthorizationOptions authOptions = UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge;
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    center.delegate = self;

    [center requestAuthorizationWithOptions:authOptions completionHandler:^(BOOL granted, NSError * _Nullable error) {
        if (error){
            @throw error.localizedDescription;
        } else if (granted) {
            [[UIApplication sharedApplication] registerForRemoteNotifications];
        }
    }];

    OWSSignalService *signalService = [OWSSignalService sharedInstance];
    self.messageFetcherJob = [[OWSMessageFetcherJob alloc] initWithMessagesManager:[TSMessagesManager sharedManager] messageSender:self.messageSender networkManager:self.networkManager signalService:signalService];

    PKPushRegistry *voipRegistry = [[PKPushRegistry alloc] initWithQueue:dispatch_get_main_queue()];
    voipRegistry.delegate = self;
    voipRegistry.desiredPushTypes = [NSSet setWithObject:PKPushTypeVoIP];
}

- (void)updateRemoteNotificationCredentials {
    NSLog(@"\n||--------------------\n||\n|| --- Account is registered: %@ \n||\n||--------------------\n\n", @([TSAccountManager isRegistered]));

    [[TSAccountManager sharedInstance] registerForPushNotificationsWithPushToken:self.token voipToken:self.voipToken success:^{
        NSLog(@"\n\n||------- \n||\n|| - TOKEN: chat PN register - SUCCESS: token: %@,\n|| - voip: %@\n||\n||------- \n", self.token, self.voipToken);

        [[EthereumAPIClient shared] registerForMainNetworkPushNotifications];

        [[EthereumAPIClient shared] registerForSwitchedNetworkPushNotificationsIfNeededWithCompletion:nil];

    } failure:^(NSError *error) {
        NSLog(@"\n\n||------- \n|| - TOKEN: chat PN register - FAILURE: %@\n||------- \n", error.localizedDescription);
    }];
}

- (void)pushRegistry:(PKPushRegistry *)registry didReceiveIncomingPushWithPayload:(PKPushPayload *)payload forType:(PKPushType)type {
    [self.messageFetcherJob runAsync];
}

- (void)pushRegistry:(PKPushRegistry *)registry didInvalidatePushTokenForType:(PKPushType)type {

}

- (void)pushRegistry:(PKPushRegistry *)registry didUpdatePushCredentials:(PKPushCredentials *)credentials forType:(PKPushType)type {
    self.voipToken = [credentials.token ows_tripToken];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    [BackgroundNotificationHandler handle:notification :^(UNNotificationPresentationOptions options) {
        completionHandler(options);
    }];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)())completionHandler {
    NSString *identifier = response.notification.request.content.threadIdentifier;
    [Navigator navigateTo:identifier animated:YES];

    completionHandler();
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler
{
    __weak typeof(self)weakSelf = self;

    [SignalNotificationHandler handleMessage:userInfo completion:^(UIBackgroundFetchResult result) {

        typeof(self)strongSelf = weakSelf;

        if (result == UIBackgroundFetchResultNewData) {
            [strongSelf.messageFetcherJob runAsync];
        }

        completionHandler(result);
    }];

    [EthereumNotificationHandler handlePayment:userInfo completion:^(UIBackgroundFetchResult result) {
        completionHandler(result);
    }];
}

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    self.token = [deviceToken hexadecimalString];
}

- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    NSLog(@"Failed to register for remote notifications. %@", error);
}

@end
