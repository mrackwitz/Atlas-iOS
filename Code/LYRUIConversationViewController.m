//
//  LYRUIConversationViewController.m
//  LayerSample
//
//  Created by Kevin Coleman on 8/31/14.
//  Copyright (c) 2014 Layer, Inc. All rights reserved.
//

#import <AssetsLibrary/AssetsLibrary.h>
#import "LYRUIConversationViewController.h"
#import "LYRUIOutgoingMessageCollectionViewCell.h"
#import "LYRUIIncomingMessageCollectionViewCell.h"
#import "LYRUIConversationCollectionViewHeader.h"
#import "LYRUIConversationCollectionViewFooter.h"
#import "LYRUIConstants.h"
#import "LYRUIDataSourceChange.h"
#import "LYRUIMessagingUtilities.h"
#import "LYRUITypingIndicatorView.h"
#import "LYRQueryController.h"
#import "LYRUIDataSourceChange.h"

@interface LYRUIConversationViewController () <UICollectionViewDataSource, UICollectionViewDelegate, LYRUIMessageInputToolbarDelegate, UIActionSheetDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIGestureRecognizerDelegate, LYRQueryControllerDelegate>

@property (nonatomic) UICollectionView *collectionView;
@property (nonatomic) UIView *inputAccessoryView;
@property (nonatomic) UILabel *typingIndicatorLabel;
@property (nonatomic) LYRUITypingIndicatorView *typingIndicatorView;
@property (nonatomic) BOOL keyboardIsOnScreen;
@property (nonatomic) CGFloat keyboardHeight;
@property (nonatomic) BOOL shouldScrollToBottom;
@property (nonatomic) BOOL shouldDisplayAvatarImage;
@property (nonatomic) CGRect addressBarRect;
@property (nonatomic) NSLayoutConstraint *typingIndicatorViewTopConstraint;
@property (nonatomic) NSMutableDictionary *typingIndicatorStatusByParticipant;
@property (nonatomic) LYRQueryController *queryController;
@property (nonatomic) NSMutableArray *objectChages;
@property (nonatomic) NSHashTable *sectionFooters;

@end

@implementation LYRUIConversationViewController

static NSString *const LYRUIIncomingMessageCellIdentifier = @"incomingMessageCellIdentifier";
static NSString *const LYRUIOutgoingMessageCellIdentifier = @"outgoingMessageCellIdentifier";
static NSString *const LYRUIMessageCellHeaderIdentifier = @"messageCellHeaderIdentifier";
static NSString *const LYRUIMessageCellFooterIdentifier = @"messageCellFooterIdentifier";

static CGFloat const LYRUITypingIndicatorHeight = 20;

+ (instancetype)conversationViewControllerWithConversation:(LYRConversation *)conversation layerClient:(LYRClient *)layerClient;
{
    NSAssert(layerClient, @"`Layer Client` cannot be nil");
    return [[self alloc] initWithConversation:conversation layerClient:layerClient];
}

- (id)initWithConversation:(LYRConversation *)conversation layerClient:(LYRClient *)layerClient
{
    self = [super init];
    if (self) {
         // Set properties from designated initializer
        _conversation = conversation;
        _layerClient = layerClient;
        
        // Set default configuration for public configuration properties
        _dateDisplayTimeInterval = 60*15;
        _showsAddressBar = NO;
        _typingIndicatorStatusByParticipant = [NSMutableDictionary dictionaryWithCapacity:conversation.participants.count];
        _sectionFooters = [NSHashTable weakObjectsHashTable];
        
        // Configure default UIAppearance Proxy
        [self configureMessageBubbleAppearance];
    }
    return self;
}

- (id)init
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Failed to call designated initializer." userInfo:nil];
    return nil;
}

#pragma mark - VC Lifecycle Methods

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor whiteColor];
    self.accessibilityLabel = @"Conversation";
    
    // Collection View Setup
    self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectZero
                                             collectionViewLayout:[[UICollectionViewFlowLayout alloc] init]];
    self.collectionView.translatesAutoresizingMaskIntoConstraints = NO;
    self.collectionView.scrollIndicatorInsets = self.collectionView.contentInset;
    self.collectionView.delegate = self;
    self.collectionView.dataSource = self;
    self.collectionView.backgroundColor = [UIColor whiteColor];
    self.collectionView.alwaysBounceVertical = TRUE;
    self.collectionView.bounces = TRUE;
    self.collectionView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.collectionView.accessibilityLabel = @"Conversation Collection View";
    [self.view addSubview:self.collectionView];
    
    // Set the accessoryView to be a Message Input Toolbar
    self.messageInputToolbar =  [LYRUIMessageInputToolbar new];
    self.messageInputToolbar.inputToolBarDelegate = self;
    [self.messageInputToolbar sizeToFit];
    self.inputAccessoryView = self.messageInputToolbar;
    [self configureSendButtonEnablement];
    
    // Set the typing indicator label
    self.typingIndicatorView = [[LYRUITypingIndicatorView alloc] init];
    self.typingIndicatorView.translatesAutoresizingMaskIntoConstraints = NO;
    self.typingIndicatorView.alpha = 0.0;
    [self.view addSubview:self.typingIndicatorView];
    
    if (!self.conversation && self.showsAddressBar) {
        self.addressBarController = [[LYRUIAddressBarViewController alloc] init];
        self.addressBarController.delegate = self;
        [self addChildViewController:self.addressBarController];
        [self.view addSubview:self.addressBarController.view];
        [self.addressBarController didMoveToParentViewController:self];
        [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.addressBarController.view attribute:NSLayoutAttributeLeft relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeLeft multiplier:1.0 constant:0.0]];
        [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.addressBarController.view attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeWidth multiplier:1.0 constant:0.0]];
        [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.addressBarController.view attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.topLayoutGuide attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0]];
        [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.addressBarController.view attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0]];
    }

    [self updateAutoLayoutConstraints];
    self.collectionView.contentInset = UIEdgeInsetsMake(0, 0, self.inputAccessoryView.intrinsicContentSize.height, 0);
    self.collectionView.scrollIndicatorInsets = UIEdgeInsetsMake(0, 0, self.inputAccessoryView.intrinsicContentSize.height, 0);
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if (self.conversation) {
        [self fetchLayerMessages];
    }
    self.objectChages = [NSMutableArray new];
    
    // Register reusable collection view cells, header and footer
    [self.collectionView registerClass:[LYRUIIncomingMessageCollectionViewCell class]
            forCellWithReuseIdentifier:LYRUIIncomingMessageCellIdentifier];
    
    [self.collectionView registerClass:[LYRUIOutgoingMessageCollectionViewCell class]
            forCellWithReuseIdentifier:LYRUIOutgoingMessageCellIdentifier];
    
    [self.collectionView registerClass:[LYRUIConversationCollectionViewHeader class]
            forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
                   withReuseIdentifier:LYRUIMessageCellHeaderIdentifier];
    
    [self.collectionView registerClass:[LYRUIConversationCollectionViewFooter class]
            forSupplementaryViewOfKind:UICollectionElementKindSectionFooter
                   withReuseIdentifier:LYRUIMessageCellFooterIdentifier];
    
    // Collection View AutoLayout Config
    [self setConversationViewTitle];
    [self scrollToBottomOfCollectionViewAnimated:NO];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self.addressBarController.addressBarView.addressBarTextView becomeFirstResponder];
    
    // Register for keyboard notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWasShown:)
                                                 name:UIKeyboardWillShowNotification object:nil];

    // Register for typing indicator notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didReceiveTypingIndicator:)
                                                 name:LYRConversationDidReceiveTypingIndicatorNotification object:self.conversation];
    self.keyboardIsOnScreen = NO;

    // Update typing indicator
    [self updateTypingIndicatorOverlay:YES];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    self.queryController = nil;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIKeyboardWillShowNotification
                                                  object:nil];

    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:LYRConversationDidReceiveTypingIndicatorNotification
                                                  object:self.conversation];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];

    if (self.addressBarController) {
        UIEdgeInsets contentInset = self.collectionView.contentInset;
        UIEdgeInsets scrollIndicatorInsets = self.collectionView.scrollIndicatorInsets;
        CGRect frame = [self.view convertRect:self.addressBarController.addressBarView.frame fromView:self.addressBarController.addressBarView.superview];
        contentInset.top = CGRectGetMaxY(frame);
        scrollIndicatorInsets.top = contentInset.top;
        self.collectionView.contentInset = contentInset;
        self.collectionView.scrollIndicatorInsets = scrollIndicatorInsets;
    }
}

- (void)dealloc
{
    self.collectionView.delegate = nil;
}

- (BOOL)canBecomeFirstResponder
{
    return YES;
}

#pragma mark - Conversation Setup Methods

- (void)fetchLayerMessages
{
    LYRQuery *query = [LYRQuery queryWithClass:[LYRMessage class]];
    query.predicate = [LYRPredicate predicateWithProperty:@"conversation" operator:LYRPredicateOperatorIsEqualTo value:self.conversation];
    query.sortDescriptors = @[ [NSSortDescriptor sortDescriptorWithKey:@"index" ascending:YES]];
    
    self.queryController = [self.layerClient queryControllerWithQuery:query];
    self.queryController.delegate = self;
    NSError *error = nil;
    BOOL success = [self.queryController execute:&error];
    if (!success) NSLog(@"LayerKit failed to execute query");
    [self.collectionView reloadData];
}

- (void)setConversation:(LYRConversation *)conversation
{
    _conversation = conversation;
    [self configureSendButtonEnablement];
    if (conversation) {
        [self fetchLayerMessages];
    } else {
        self.queryController = nil;
        [self.collectionView reloadData];
    }
}

- (void)setConversationViewTitle
{
    if (!self.conversation) {
        self.title = @"New Message";
    } else if (1 >= self.conversation.participants.count) {
        self.title = @"Personal";
    } else if (2 >= self.conversation.participants.count) {
        [self.typingIndicatorView updateLabelInset:10];
        self.shouldDisplayAvatarImage = NO;
        NSMutableSet *participants = [self.conversation.participants mutableCopy];
        [participants removeObject:self.layerClient.authenticatedUserID];
        id<LYRUIParticipant> participant = [self participantForIdentifier:[[participants allObjects] lastObject]];
        if (participant) {
            self.title = participant.firstName;
        } else {
            self.title = @"Unknown";
        }
    } else {
        [self.typingIndicatorView updateLabelInset:48];
        self.shouldDisplayAvatarImage = YES;
        self.title = @"Group";
    }
    self.title = self.conversationTitle ?: self.title;
}

#pragma mark - Conversation title

- (void)setConversationTitle:(NSString *)conversationTitle
{
    _conversationTitle = conversationTitle;
    
    // Update UI if possible
    if (self.isViewLoaded) {
        [self setConversationViewTitle];
    }
}

# pragma mark - Collection View Data Source

/**
 
 LAYER - The `LYRUIConversationViewController` component uses `LYRMessageParts` to represent rows.
 
 */
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    // MessageParts correspond to rows in a section
    LYRMessage *message = [self.queryController objectAtIndexPath:[NSIndexPath indexPathForRow:section inSection:0]];
    return message.parts.count;
}

/**
 
 LAYER - The `LYRUIConversationViewController` component uses `LYRMessages` to represent sections.
 
 */
- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    // Messages correspond to sections
    NSInteger numberOfSections = [self.queryController numberOfObjectsInSection:0];
    return numberOfSections;
}

/**
 
 LAYER - Configuring a subclass of `LYRUIMessageCollectionViewCell` to be displayed on screen. `LayerUIKit` supports both
 `LYRUIIncomingMessageCollectionViewCell` and `LYRUIOutgoingMessageCollectionViewCell`.
 
 */
- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    LYRMessage *message = [self.queryController objectAtIndexPath:[NSIndexPath indexPathForRow:indexPath.section inSection:0]];
    LYRUIMessageCollectionViewCell <LYRUIMessagePresenting> *cell;
    if ([self.layerClient.authenticatedUserID isEqualToString:message.sentByUserID]) {
        // If the message was sent by the currently authenticated user, it is outgoing
        cell =  [self.collectionView dequeueReusableCellWithReuseIdentifier:LYRUIOutgoingMessageCellIdentifier forIndexPath:indexPath];
    } else {
        // If the message was sent by someone other than the currently authenticated user, it is incoming
        cell = [self.collectionView dequeueReusableCellWithReuseIdentifier:LYRUIIncomingMessageCellIdentifier forIndexPath:indexPath];
    }
    [self configureCell:cell forMessage:message indexPath:indexPath];
    return cell;
}

/**
 
 LAYER - Extracting the proper message part and analyzing its properties to determine the cell configuration.
 
 */
- (void)configureCell:(LYRUIMessageCollectionViewCell <LYRUIMessagePresenting> *)cell forMessage:(LYRMessage *)message indexPath:(NSIndexPath *)indexPath
{
    LYRMessagePart *messagePart = [message.parts objectAtIndex:indexPath.row];
    [cell presentMessagePart:messagePart];
    [cell updateWithMessageSentState:message.isSent];
    [cell updateWithBubbleViewWidth:[self sizeForItemAtIndexPath:indexPath].width];
    [cell shouldDisplayAvatarImage:self.shouldDisplayAvatarImage];

    if ([self shouldDisplayParticipantInfo:indexPath]) {
        [cell updateWithParticipant:[self participantForIdentifier:message.sentByUserID]];
    } else {
        [cell updateWithParticipant:nil];
    }
    if ([self.dataSource respondsToSelector:@selector(conversationViewController:shouldUpdateRecipientStatusForMessage:)]) {
        if ([self.dataSource conversationViewController:self shouldUpdateRecipientStatusForMessage:message]) {
            [self updateRecipientStatusForMessage:message];
        }
    }
}

#pragma mark – UICollectionViewDelegateFlowLayout Methods

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self.delegate respondsToSelector:@selector(conversationViewController:didSelectMessage:)]) {
        LYRMessage *message = [self.queryController objectAtIndexPath:[NSIndexPath indexPathForRow:indexPath.section inSection:0]];
        [self.delegate conversationViewController:self didSelectMessage:message];
    }
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    CGFloat width = self.collectionView.bounds.size.width;
    CGFloat height = [self sizeForItemAtIndexPath:indexPath].height;
    return CGSizeMake(width, height);
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath
{
    LYRMessage *message = [self.queryController objectAtIndexPath:[NSIndexPath indexPathForRow:indexPath.section inSection:0]];
    if (kind == UICollectionElementKindSectionHeader ) {
        LYRUIConversationCollectionViewHeader *header = [self.collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:LYRUIMessageCellHeaderIdentifier forIndexPath:indexPath];
        // Should we display a sender label?
        if ([self shouldDisplaySenderLabelForSection:indexPath.section]) {
            id<LYRUIParticipant>participant = [self participantForIdentifier:message.sentByUserID];
            if(participant) {
                [header updateWithAttributedStringForParticipantName:[[NSAttributedString alloc] initWithString:participant.fullName]];
            } else {
                [header updateWithAttributedStringForParticipantName:[[NSAttributedString alloc] initWithString:@"No Matching Participant"]];
            }
        }
        // Should we display a date label?
        if ([self shouldDisplayDateLabelForSection:indexPath.section]) {
            if ([self.dataSource respondsToSelector:@selector(conversationViewController:attributedStringForDisplayOfDate:)]) {
                NSAttributedString *dateString;
                if (message.sentAt) {
                    dateString = [self.dataSource conversationViewController:self attributedStringForDisplayOfDate:message.sentAt];
                } else {
                    dateString = [self.dataSource conversationViewController:self attributedStringForDisplayOfDate:[NSDate date]];
                }
                NSAssert([dateString isKindOfClass:[NSAttributedString class]], @"`Date String must be an attributed string");
                [header updateWithAttributedStringForDate:dateString];
            } else {
                @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"LYRUIConversationViewControllerDataSource must return an attributed string for Date" userInfo:nil];
            }
        }
        return header;
    } else {
        LYRUIConversationCollectionViewFooter *footer = [self.collectionView dequeueReusableSupplementaryViewOfKind:kind withReuseIdentifier:LYRUIMessageCellFooterIdentifier forIndexPath:indexPath];
        [self configureFooter:footer atIndexPath:indexPath];
        [self.sectionFooters addObject:footer];
        return footer;
    }
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout referenceSizeForHeaderInSection:(NSInteger)section
{
    CGFloat height = 0;
    LYRMessage *message = [self.queryController objectAtIndexPath:[NSIndexPath indexPathForRow:section inSection:0]];
    if (section > 0) {
        // 1. If previous message was sent by a different user, add 10px
        LYRMessage *previousMessage = [self.queryController objectAtIndexPath:[NSIndexPath indexPathForRow:section - 1 inSection:0]];;
        if (![message.sentByUserID isEqualToString:previousMessage.sentByUserID]) {
            height += 10;
        }
    }
    // 2. If date label is shown, add 30px
    if ([self shouldDisplayDateLabelForSection:section]) {
        height += 30;
    }
    // 3. If sender label is shown, add 30px
    if ([self shouldDisplaySenderLabelForSection:section]) {
        height += 30;
    }
    return CGSizeMake([[UIScreen mainScreen] bounds].size.width, height);
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout referenceSizeForFooterInSection:(NSInteger)section
{
    // If we display a read receipt...
    if ([self shouldDisplayReadReceiptForSection:section]) {
        return CGSizeMake([[UIScreen mainScreen] bounds].size.width, 28);
    }
    return CGSizeMake([[UIScreen mainScreen] bounds].size.width, 6);
}

#pragma mark - Recipient Status Methods

- (void)updateRecipientStatusForMessage:(LYRMessage *)message
{
    if (!message) return;
    NSNumber *recipientStatus = [message.recipientStatusByUserID objectForKey:self.layerClient.authenticatedUserID];
    if (![recipientStatus isEqualToNumber:[NSNumber numberWithInteger:LYRRecipientStatusRead]] ) {
        NSError *error;
        BOOL success = [message markAsRead:&error];
        if (success) {
            NSLog(@"Message successfully marked as read");
        } else {
            NSLog(@"Failed to mark message as read with error %@", error);
        }
    }
}

#pragma mark - UI Configuration Methods

- (BOOL)shouldDisplayDateLabelForSection:(NSUInteger)section
{
    // Always show date label for the first section
    if (section == 0) return YES;
    LYRMessage *message = [self.queryController objectAtIndexPath:[NSIndexPath indexPathForRow:section inSection:0]];
    if (section > 0) {
        LYRMessage *previousMessage = [self.queryController objectAtIndexPath:[NSIndexPath indexPathForRow:section - 1 inSection:0]];
        NSTimeInterval interval = [message.receivedAt timeIntervalSinceDate:previousMessage.receivedAt];
        // If it has been 60min since last message, show date label
        if (interval > self.dateDisplayTimeInterval) {
            return YES;
        }
    }
    // Otherwise, don't show date label
    return NO;
}

- (BOOL)shouldDisplaySenderLabelForSection:(NSUInteger)section
{
    // 1. If conversation only has 2 participnat, don't show sender label
    if (!(self.conversation.participants.count > 2)) {
        return NO;
    }
    
    // 2. If the message if from current user, don't show sender label
    LYRMessage *message = [self.queryController objectAtIndexPath:[NSIndexPath indexPathForRow:section inSection:0]];
    if ([message.sentByUserID isEqualToString:self.layerClient.authenticatedUserID]) {
        return NO;
    }

    // 3. If the previous message was send by the same user, don't show label
    if (section > 0) {
        LYRMessage *previousMessage = [self.queryController objectAtIndexPath:[NSIndexPath indexPathForRow:section - 1 inSection:0]];
        if ([previousMessage.sentByUserID isEqualToString:message.sentByUserID]) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)shouldDisplayReadReceiptForSection:(NSUInteger)section
{
    // Only show read receipt if last message was send by currently authenticated user
    LYRMessage *message = [self.queryController objectAtIndexPath:[NSIndexPath indexPathForRow:section inSection:0]];
    if ((section == ([self.queryController numberOfObjectsInSection:0] - 1)) && [message.sentByUserID isEqualToString:self.layerClient.authenticatedUserID]) {
        return YES;
    }
    return NO;
}

- (BOOL)shouldDisplayParticipantInfo:(NSIndexPath *)indexPath
{
    if (!self.shouldDisplayAvatarImage) return NO;
    LYRMessage *message = [self.queryController objectAtIndexPath:[NSIndexPath indexPathForRow:indexPath.section inSection:0]];
    if ([message.sentByUserID isEqualToString:self.layerClient.authenticatedUserID]) {
        return NO;
    }
    if (indexPath.section < self.collectionView.numberOfSections - 1) {
        LYRMessage *nextMessage = [self.queryController objectAtIndexPath:[NSIndexPath indexPathForRow:indexPath.section + 1 inSection:0]];
        // If the next message is sent by the same user, no
        if ([nextMessage.sentByUserID isEqualToString:message.sentByUserID]) {
            return FALSE;
        }
    }
    return TRUE;
}

- (CGSize)sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    LYRMessage *message = [self.queryController objectAtIndexPath:[NSIndexPath indexPathForRow:indexPath.section inSection:0]];
    LYRMessagePart *part = [message.parts objectAtIndex:indexPath.row];
    
    CGSize size;
    if ([part.MIMEType isEqualToString:LYRUIMIMETypeTextPlain]) {
        NSString *text = [[NSString alloc] initWithData:part.data encoding:NSUTF8StringEncoding];
        size = LYRUITextPlainSize(text, [[LYRUIOutgoingMessageCollectionViewCell appearance] messageTextFont]);
        size.height = size.height + 16; // Adding 16 to account for default vertical padding for text in bubble view
    } else if ([part.MIMEType isEqualToString:LYRUIMIMETypeImageJPEG] || [part.MIMEType isEqualToString:LYRUIMIMETypeImagePNG]) {
        UIImage *image = [UIImage imageWithData:part.data];
        size = LYRUIImageSize(image);
    } else if ([part.MIMEType isEqualToString:LYRUIMIMETypeLocation]) {
        size = CGSizeMake(200, 200);
    } else {
        size = CGSizeMake(320, 10);
    }
    return size;
}

#pragma mark - Keyboard Nofifications

- (void)keyboardWasShown:(NSNotification*)notification
{
    if (self.keyboardIsOnScreen) {
        self.keyboardIsOnScreen = NO;
    } else {
        self.keyboardIsOnScreen = YES;
    }
    
    self.keyboardHeight = [[[notification userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue].size.height;
    [UIView beginAnimations:nil context:NULL];
    [self updateTypingIndicatorOverlay:NO];
    [UIView setAnimationDuration:[notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue]];
    [UIView setAnimationCurve:[notification.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue]];
    [UIView setAnimationBeginsFromCurrentState:YES];
    [self updateCollectionViewInsets];
    [UIView commitAnimations];
    if (self.keyboardIsOnScreen) {
        [self scrollToBottomOfCollectionViewAnimated:TRUE];
    }
}

#pragma mark - Typing indicator notifications

- (void)didReceiveTypingIndicator:(NSNotification *)notification
{
    NSString *participantID = notification.userInfo[LYRTypingIndicatorParticipantUserInfoKey];
    self.typingIndicatorStatusByParticipant[participantID] = notification.userInfo[LYRTypingIndicatorValueUserInfoKey];
    [self updateTypingIndicatorOverlay:YES];
}

- (void)updateTypingIndicatorOverlay:(BOOL)animated
{
    NSMutableArray *participantsTyping = [NSMutableArray array];
    
    // Collect participant's first names, but no more than three.
    [self.typingIndicatorStatusByParticipant.allKeys enumerateObjectsUsingBlock:^(NSString *participantID, NSUInteger idx, BOOL *stop) {
        if ([self.typingIndicatorStatusByParticipant[participantID] unsignedIntegerValue] == LYRTypingDidBegin) {
            [participantsTyping addObject:[self participantForIdentifier:participantID].firstName];
            if (idx++ > 3) *stop = YES; // stop adding participants to the string if there are more that 3 people typing at once
        }
    }];
    
    // If there are more than three participants, add "others" at the end.
    if (participantsTyping.count >= 3) [participantsTyping addObject:@"others"];
    
    // Seperate the list of participants with a comma.
    NSString *commaSeperatedParticipants = [participantsTyping componentsJoinedByString:@", "];
    
    // Replace the last comma with an "and" word.
    NSRange lastCommaRange = [commaSeperatedParticipants rangeOfString:@", " options:NSBackwardsSearch];
    if (lastCommaRange.location != NSNotFound) {
        commaSeperatedParticipants = [commaSeperatedParticipants stringByReplacingOccurrencesOfString:@", " withString:@" and " options:NSBackwardsSearch range:lastCommaRange];
    }
    
    // Check if the collection view is scrolled to the bottom
    BOOL isScrolledToBottom = (self.collectionView.contentOffset.y >= (self.collectionView.contentSize.height - self.collectionView.bounds.size.height));
    
    // Figure out if we can display the typing indicator label, based
    // on the scroll position.
    BOOL visible = (participantsTyping.count >= 1) && isScrolledToBottom;
    if (participantsTyping.count) {
        [self.typingIndicatorView setText: [NSString stringWithFormat:@"%@ %@ typing...", commaSeperatedParticipants, participantsTyping.count > 1 ? @"are" : @"is"]];
    }
    
    self.typingIndicatorViewTopConstraint.constant = -self.inputAccessoryView.frame.size.height - LYRUITypingIndicatorHeight;
    [self.view setNeedsUpdateConstraints];
    [UIView animateWithDuration:animated ? (visible ? 0.3 : 0.1) : 0 animations:^{
        self.typingIndicatorView.alpha = visible ? 1.0 : 0.0;
        [self updateCollectionViewInsets];
        if (visible) [self scrollToBottomOfCollectionViewAnimated:YES];
        [self.view layoutIfNeeded];
    }];

}

#pragma mark - LYRUIMessageInputToolbar Delegate Methods

- (void)messageInputToolbar:(LYRUIMessageInputToolbar *)messageInputToolbar didTapLeftAccessoryButton:(UIButton *)leftAccessoryButton
{
    UIActionSheet *actionSheet = [[UIActionSheet alloc]
                                  initWithTitle:nil
                                  delegate:self
                                  cancelButtonTitle:@"Cancel"
                                  destructiveButtonTitle:nil
                                  otherButtonTitles:@"Take Photo", @"Last Photo Taken", @"Photo Library", nil];
    [actionSheet showInView:self.view];
}

/**
 
 LAYER - Sending a message through Layer. The `LYRUIMessageInputToolbar` informs the controller that the `rightAccessoryButton` 
 property (representing the `SEND` button) was tapped.
 
 */
- (void)messageInputToolbar:(LYRUIMessageInputToolbar *)messageInputToolbar didTapRightAccessoryButton:(UIButton *)rightAccessoryButton
{
    if (!self.conversation) return;
    if (messageInputToolbar.messageParts.count > 0) {
        NSMutableArray *messagePartsToSend = [NSMutableArray new];
        for (id part in messageInputToolbar.messageParts){
            if ([part isKindOfClass:[NSString class]]) {
                [messagePartsToSend addObject:LYRUIMessagePartWithText(part)];
            }
            if ([part isKindOfClass:[UIImage class]]) {
                [messagePartsToSend addObject:LYRUIMessagePartWithJPEGImage(part)];
            }
            if ([part isKindOfClass:[CLLocation class]]) {
                [messagePartsToSend addObject:LYRUIMessagePartWithLocation(part)];
            }
        }
        id<LYRUIParticipant>sender = [self participantForIdentifier:self.layerClient.authenticatedUserID];
        NSString *pushText = [self pushNotificationStringForMessageParts:messagePartsToSend];
        NSString *text = [NSString stringWithFormat:@"%@: %@", [sender fullName], pushText];
        LYRMessage *message = [self.layerClient newMessageWithParts:messagePartsToSend options:@{LYRMessagePushNotificationAlertMessageKey : text,
                                                                                                 LYRMessagePushNotificationSoundNameKey : @"default"} error:nil];
        [self sendMessage:message];
        if (self.addressBarController) [self.addressBarController setPermanent];
    }
}

/**
 
 LAYER - Input tool bar began typing, so we can send a typing indicator.
 
 */
- (void)messageInputToolbarDidBeginTyping:(LYRUIMessageInputToolbar *)messageInputToolbar
{
    if (!self.conversation) return;
    [self.conversation sendTypingIndicator:LYRTypingDidBegin];
}

/**
 
 LAYER - Input tool bar ended typing, so we can terminate the typing indicator.
 
 */
- (void)messageInputToolbarDidEndTyping:(LYRUIMessageInputToolbar *)messageInputToolbar
{
    if (!self.conversation) return;
    [self.conversation sendTypingIndicator:LYRTypingDidFinish];
}

#pragma mark - Message Send Methods

- (NSString *)pushNotificationStringForMessageParts:(NSArray *)messageParts
{
    NSString *pushText;
    if ( [self.dataSource respondsToSelector:@selector(conversationViewController:pushNotificationTextForMessageParts:)]) {
        pushText = [self.dataSource conversationViewController:self pushNotificationTextForMessageParts:messageParts];
    } 
    return pushText;
}

- (void)sendMessage:(LYRMessage *)message
{
    self.shouldScrollToBottom = TRUE;

    NSError *error;
    BOOL success = [self.conversation sendMessage:message error:&error];
    if (success) {
        if ([self.delegate respondsToSelector:@selector(conversationViewController:didSendMessage:)]) {
            [self.delegate conversationViewController:self didSendMessage:message];
        }
    } else {
        if ([self.delegate respondsToSelector:@selector(conversationViewController:didFailSendingMessage:error:)]) {
            [self.delegate conversationViewController:self didFailSendingMessage:message error:error];
        }
    }
}

#pragma mark UIActionSheetDelegate Methods

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    switch (buttonIndex) {
        case 0:
            [self displayImagePickerWithSourceType:UIImagePickerControllerSourceTypeCamera];
            break;
            
        case 1:
           [self captureLastPhotoTaken];
            break;
          
        case 2:
            [self displayImagePickerWithSourceType:UIImagePickerControllerSourceTypePhotoLibrary];
            break;
            
        default:
            break;
    }
}

#pragma mark UIImagePicker Methods

- (void)displayImagePickerWithSourceType:(UIImagePickerControllerSourceType)sourceType;
{
    [[(LYRUIMessageInputToolbar *)self.inputAccessoryView textInputView] resignFirstResponder];
    BOOL pickerSourceTypeAvailable = [UIImagePickerController isSourceTypeAvailable:sourceType];
    if (pickerSourceTypeAvailable) {
        UIImagePickerController *picker = [[UIImagePickerController alloc] init];
        picker.delegate = self;
        picker.sourceType = sourceType;
        [self.navigationController presentViewController:picker animated:YES completion:nil];
    }
}

- (void)captureLastPhotoTaken
{
    // Credit goes to @iBrad Apps on Stack Overflow
    // http://stackoverflow.com/questions/8867496/get-last-image-from-photos-app
    
    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
    
    // Enumerate just the photos and videos group by using ALAssetsGroupSavedPhotos.
    [library enumerateGroupsWithTypes:ALAssetsGroupSavedPhotos usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
        
        // Within the group enumeration block, filter to enumerate just photos.
        [group setAssetsFilter:[ALAssetsFilter allPhotos]];
        
        // Chooses the photo at the last index
        [group enumerateAssetsWithOptions:NSEnumerationReverse usingBlock:^(ALAsset *alAsset, NSUInteger index, BOOL *innerStop) {
            
            // The end of the enumeration is signaled by asset == nil.
            if (alAsset) {
                ALAssetRepresentation *representation = [alAsset defaultRepresentation];
                UIImage *latestPhoto = [UIImage imageWithCGImage:[representation fullScreenImage]];
                
                // Stop the enumerations
                *stop = YES; *innerStop = YES;
                
                // Do something interesting with the AV asset.
                [(LYRUIMessageInputToolbar *)self.inputAccessoryView insertImage:latestPhoto];
            }
        }];
    } failureBlock:nil];
}

#pragma mark UIImagePickerController Delegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
    NSString *mediaType = [info objectForKey:@"UIImagePickerControllerMediaType"];
    if ([mediaType isEqualToString:@"public.image"]) {
        UIImage *selectedImage = (UIImage *)[info objectForKey:UIImagePickerControllerOriginalImage];
        [(LYRUIMessageInputToolbar *)self.inputAccessoryView insertImage:selectedImage];
    }
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [self.navigationController dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark CollectionView Content Inset Methods

- (void)updateCollectionViewInsets
{
    UIEdgeInsets existing = self.collectionView.contentInset;
    CGFloat keyboardHeight = self.keyboardHeight < 1.0 ? self.inputAccessoryView.frame.size.height : self.keyboardHeight;
    keyboardHeight += self.typingIndicatorView.alpha ? LYRUITypingIndicatorHeight : 0;
    self.collectionView.contentInset = UIEdgeInsetsMake(existing.top, 0, keyboardHeight, 0);
    self.collectionView.scrollIndicatorInsets = UIEdgeInsetsMake(existing.top, 0, keyboardHeight, 0);
}

- (CGPoint)bottomOffset
{
    CGFloat contentSizeHeight = self.collectionView.collectionViewLayout.collectionViewContentSize.height;
    CGFloat collectionViewFrameHeight = self.collectionView.frame.size.height;
    CGFloat collectionViewBottomInset = self.collectionView.contentInset.bottom;
    CGFloat collectionViewTopInset = self.collectionView.contentInset.top;
    CGPoint offset = CGPointMake(0, MAX(-collectionViewTopInset, contentSizeHeight - (collectionViewFrameHeight - collectionViewBottomInset)));
    return offset;
}

#pragma mark Handle Device Rotation

-(void)willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
                               duration:(NSTimeInterval)duration
{
    [self.collectionView.collectionViewLayout invalidateLayout];
    
}

#pragma mark Notification Observer Delegate Methods

- (void)queryControllerWillChangeContent:(LYRQueryController *)queryController
{
   NSLog(@"Changes Began");
}

- (void)queryController:(LYRQueryController *)controller
        didChangeObject:(id)object
            atIndexPath:(NSIndexPath *)indexPath
          forChangeType:(LYRQueryControllerChangeType)type
           newIndexPath:(NSIndexPath *)newIndexPath
{
    [self.objectChages addObject:[LYRUIDataSourceChange changeObjectWithType:type newIndex:newIndexPath.row currentIndex:indexPath.row]];
}

- (void)queryControllerDidChangeContent:(LYRQueryController *)queryController
{
    __block BOOL shouldScroll;
    [self.collectionView performBatchUpdates:^{
        for (LYRUIDataSourceChange *change in self.objectChages) {
            switch (change.type) {
                case LYRQueryControllerChangeTypeInsert:
                    [self.collectionView insertSections:[NSIndexSet indexSetWithIndex:change.newIndex]];
                    shouldScroll = YES;
                    break;
                    
                case LYRQueryControllerChangeTypeMove:
                    [self.collectionView moveSection:change.currentIndex toSection:change.newIndex];
                    break;
                    
                case LYRQueryControllerChangeTypeDelete:
                    [self.collectionView deleteSections:[NSIndexSet indexSetWithIndex:change.currentIndex]];
                    break;
                    
                case LYRQueryControllerChangeTypeUpdate:
                    [self.collectionView reloadSections:[NSIndexSet indexSetWithIndex:change.currentIndex]];
                    break;
                    
                default:
                    break;
            }
        }
        [self.objectChages removeAllObjects];
    } completion:^(BOOL finished) {
//        if (shouldScroll)  {
            [self scrollToBottomOfCollectionViewAnimated:NO];
//        }
    }];

    // Since each section's footer content depends on the existence of other messages, we need to update footers even when the corresponding message to a footer has not changed.
    for (LYRUIConversationCollectionViewFooter *footer in self.sectionFooters) {
        NSIndexPath *queryControllerIndexPath = [self.queryController indexPathForObject:footer.message];
        if (!queryControllerIndexPath) continue;
        NSIndexPath *collectionViewIndexPath = [NSIndexPath indexPathForItem:0 inSection:queryControllerIndexPath.row];
        [self configureFooter:footer atIndexPath:collectionViewIndexPath];
    }
}

- (void)scrollToBottomOfCollectionViewAnimated:(BOOL)animated
{
    [self.collectionView setContentOffset:[self bottomOffset] animated:animated];
}

- (id<LYRUIParticipant>)participantForIdentifier:(NSString *)identifier
{
    if ([self.dataSource respondsToSelector:@selector(conversationViewController:participantForIdentifier:)]) {
        return [self.dataSource conversationViewController:self participantForIdentifier:identifier];
    } else {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"LYRUIConversationViewControllerDelegate must return a particpant for an identifier" userInfo:nil];
    }
}

#pragma mark - Address Bar View Controller Delegate Methods

- (void)addressBarViewControllerDidBeginSearching:(LYRUIAddressBarViewController *)addressBarViewController
{
    self.inputAccessoryView.alpha = 0.0f;
}

- (void)addressBarViewControllerDidEndSearching:(LYRUIAddressBarViewController *)addressBarViewController
{
    self.inputAccessoryView.alpha = 1.0f;
}

- (void)addressBarViewController:(LYRUIAddressBarViewController *)addressBarViewController didSelectParticipant:(id<LYRUIParticipant>)participant
{
    [self configureConversationWithAddressBar:addressBarViewController];
}

- (void)addressBarViewController:(LYRUIAddressBarViewController *)addressBarViewController didRemoveParticipant:(id<LYRUIParticipant>)participant
{
    [self configureConversationWithAddressBar:addressBarViewController];
}

- (void)configureConversationWithAddressBar:(LYRUIAddressBarViewController *)addressBarViewController
{
    NSSet *participants = [addressBarViewController.selectedParticipants valueForKey:@"participantIdentifier"];
    if (!participants.count) {
        self.conversation = nil;
    } else {
        LYRConversation *conversation = [self conversationWithParticipants:participants];
        if (conversation) {
            self.conversation = conversation;
        } else {
            self.conversation = [self.layerClient newConversationWithParticipants:participants options:nil error:nil];
        }
        if (self.conversation.participants.count > 2) self.shouldDisplayAvatarImage = YES;
    }
    [self setConversationViewTitle];
    [self.collectionView.collectionViewLayout invalidateLayout];
    [self.collectionView reloadData];
    [self scrollToBottomOfCollectionViewAnimated:NO];
    [UIView animateWithDuration:0.5 animations:^{
        self.collectionView.alpha = 1.0f;
    }];
}

- (LYRConversation *)conversationWithParticipants:(NSSet *)participants
{
    NSMutableSet *set = [participants mutableCopy];
    [set addObject:self.layerClient.authenticatedUserID];
    LYRQuery *query = [LYRQuery queryWithClass:[LYRConversation class]];
    query.predicate = [LYRPredicate predicateWithProperty:@"participants" operator:LYRPredicateOperatorIsEqualTo value:set];
    return [[self.layerClient executeQuery:query error:nil] lastObject];
}

#pragma mark Send Button Enablement

- (void)configureSendButtonEnablement
{
    self.messageInputToolbar.canEnableSendButton = [self shouldAllowSendButtonEnablement];
}

- (BOOL)shouldAllowSendButtonEnablement
{
    if (!self.conversation) return NO;
    return YES;
}

#pragma mark Default Message Cell Appearance

- (void)configureMessageBubbleAppearance
{
    [[LYRUIOutgoingMessageCollectionViewCell appearance] setMessageTextColor:[UIColor whiteColor]];
    [[LYRUIOutgoingMessageCollectionViewCell appearance] setMessageTextFont:LSMediumFont(14)];
    [[LYRUIOutgoingMessageCollectionViewCell appearance] setBubbleViewColor:LSBlueColor()];
    [[LYRUIOutgoingMessageCollectionViewCell appearance] setPendingBubbleViewColor:LSBlueColor()];
    
    [[LYRUIIncomingMessageCollectionViewCell appearance] setMessageTextColor:[UIColor blackColor]];
    [[LYRUIIncomingMessageCollectionViewCell appearance] setMessageTextFont:LSMediumFont(14)];
    [[LYRUIIncomingMessageCollectionViewCell appearance] setBubbleViewColor:LSLighGrayColor()];
    
    [[LYRUIAvatarImageView appearance] setInitialViewBackgroundColor:LSGrayColor()];
    [[LYRUIAvatarImageView appearance] setInitialColor:[UIColor blackColor]];
    [[LYRUIAvatarImageView appearance] setInitialFont:LSLightFont(14)];
}

#pragma mark - Auto Layout Configuration

- (void)updateAutoLayoutConstraints
{
    //********** Collection View Constraints **********//
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.collectionView
                                                          attribute:NSLayoutAttributeLeft
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeLeft
                                                         multiplier:1.0
                                                           constant:0]];
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.collectionView
                                                          attribute:NSLayoutAttributeRight
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeRight
                                                         multiplier:1.0
                                                           constant:0]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.collectionView
                                                          attribute:NSLayoutAttributeTop
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeTop
                                                         multiplier:1.0
                                                           constant:0]];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.collectionView
                                                          attribute:NSLayoutAttributeBottom
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeBottom
                                                         multiplier:1.0
                                                           constant:0]];
    
    //********** Typing Indicator View Constraints **********//
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.typingIndicatorView
                                                          attribute:NSLayoutAttributeLeft
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeLeft
                                                         multiplier:1.0
                                                           constant:0]];
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.typingIndicatorView
                                                          attribute:NSLayoutAttributeWidth
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:self.view
                                                          attribute:NSLayoutAttributeWidth
                                                         multiplier:1.0
                                                           constant:0]];
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.typingIndicatorView
                                                          attribute:NSLayoutAttributeHeight
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:nil
                                                          attribute:NSLayoutAttributeNotAnAttribute
                                                         multiplier:1.0
                                                           constant:LYRUITypingIndicatorHeight]];
   
    self.typingIndicatorViewTopConstraint = [NSLayoutConstraint constraintWithItem:self.typingIndicatorView
                                                                         attribute:NSLayoutAttributeTop
                                                                         relatedBy:NSLayoutRelationEqual
                                                                            toItem:self.view
                                                                         attribute:NSLayoutAttributeBottom
                                                                        multiplier:1.0
                                                                          constant:0];
    [self.view addConstraint:self.typingIndicatorViewTopConstraint];
}

#pragma mark - Helpers

- (void)configureFooter:(LYRUIConversationCollectionViewFooter *)footer atIndexPath:(NSIndexPath *)indexPath
{
    NSIndexPath *queryControllerIndexPath = [NSIndexPath indexPathForRow:indexPath.section inSection:0];
    LYRMessage *message = [self.queryController objectAtIndexPath:queryControllerIndexPath];
    footer.message = message;
    if ([self shouldDisplayReadReceiptForSection:indexPath.section]) {
        if ([self.dataSource respondsToSelector:@selector(conversationViewController:attributedStringForDisplayOfRecipientStatus:)]) {
            NSAttributedString *recipientStatusString = [self.dataSource conversationViewController:self attributedStringForDisplayOfRecipientStatus:message.recipientStatusByUserID];
            NSAssert([recipientStatusString isKindOfClass:[NSAttributedString class]], @"`Date String must be an attributed string");
            [footer updateWithAttributedStringForRecipientStatus:recipientStatusString];
        } else {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"LYRUIConversationViewControllerDataSource must return an attributed string for recipient status" userInfo:nil];
        }
    } else {
        [footer updateWithAttributedStringForRecipientStatus:nil];
    }
}

@end
