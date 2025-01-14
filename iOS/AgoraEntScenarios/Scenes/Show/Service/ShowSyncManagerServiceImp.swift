//
//  ShowSyncManagerServiceImp.swift
//  AgoraEntScenarios
//
//  Created by wushengtao on 2022/11/3.
//

import Foundation
import UIKit
import AgoraSyncManager

private let kSceneId = "scene_show"

private let SYNC_MANAGER_MESSAGE_COLLECTION = "show_message_collection"
private let SYNC_MANAGER_SEAT_APPLY_COLLECTION = "show_seat_apply_collection"
private let SYNC_MANAGER_SEAT_INVITATION_COLLECTION = "show_seat_invitation_collection"
private let SYNC_MANAGER_PK_INVITATION_COLLECTION = "show_pk_invitation_collection"
private let SYNC_MANAGER_INTERACTION_COLLECTION = "show_interaction_collection"


enum ShowError: Int, Error {
    case unknown = 0                   //unknown error
    case networkError                  //network fail
    case pkInteractionMaximumReach     //pk interaction reach the maximum
    case seatInteractionMaximumReach   //seat interaction reach the maximum
    case userCannotAccept             //reject message if in robot room
    
    func desc() -> String {
        switch self {
        case .networkError:
            return "network fail"
        case .pkInteractionMaximumReach:
            return "show_error_pk_interaction_exist".show_localized
        case .seatInteractionMaximumReach:
            return "show_error_seat_interaction_exist".show_localized
        case .userCannotAccept:
            return "show_error_interaction_rejected_by_owner".show_localized
        default:
            return "unknown error"
        }
    }
    
    func toNSError() -> NSError {
        return NSError(domain: "Show Service Error", code: rawValue, userInfo: [ NSLocalizedDescriptionKey : self.desc()])
    }
}

extension SyncError {
    func toNSError() ->NSError {
        return NSError(domain: self.message, code: code, userInfo: nil)
    }
}

private func agoraAssert(_ message: String) {
    agoraAssert(false, message)
}

private func agoraAssert(_ condition: Bool, _ message: String) {
    #if DEBUG
//    assert(condition, message)
    #else
    #endif
    if condition {
        return
    }
    
    showLogger.error(message, context: "Service")
}

private func agoraPrint(_ message: String) {
    showLogger.info(message, context: "Service")
}

class ShowSyncManagerServiceImp: NSObject, ShowServiceProtocol {
    private let uniqueId: String = NSString.withUUID().md5()!
    fileprivate var roomList: [ShowRoomListModel]? {
        set {
            AppContext.shared.showRoomList = newValue
        }
        get {
            return AppContext.shared.showRoomList
        }
    }
    fileprivate var room: ShowRoomListModel? {
        return self.roomList?.filter({ $0.roomId == roomId}).first
    }
    private var userList: [ShowUser] = [ShowUser]()
    private var messageList: [ShowMessage] = [ShowMessage]()
    private var seatApplyList: [ShowMicSeatApply] = [ShowMicSeatApply]()
//    private var seatInvitationList: [ShowMicSeatInvitation] = [ShowMicSeatInvitation]()
    private var pkInvitationList: [ShowPKInvitation] = [ShowPKInvitation]()
    private var interactionList: [ShowInteractionInfo] = [ShowInteractionInfo]()
    //interaction List in sending queue
    private var interactionPaddingIdsSet: Set<String> = Set<String>()
    
    private weak var subscribeDelegate: ShowSubscribeServiceProtocol?
    
    private var userMuteLocalAudio:Bool = false
    
    private var createPkInvitationClosure: ((NSError?) -> Void)?
    
    //create pk invitation map
    private var pkCreatedInvitationMap: [String: ShowPKInvitation] = [String: ShowPKInvitation]()
    
    fileprivate var roomId: String?
    
    fileprivate var connectState: SocketConnectState?
    
    deinit {
        agoraPrint("deinit-- ShowSyncManagerServiceImp")
        SyncUtilsWrapper.cleanScene(uniqueId: uniqueId)
    }
    
    // MARK: Private
    private func getRoomId() -> String {
        guard let _roomId = roomId else {
//            agoraAssert("roomId == nil")
            return ""
        }

        return _roomId
    }
    
    fileprivate func isOwner(_ room: ShowRoomListModel) -> Bool {
        return room.ownerId == VLUserCenter.user.id
    }
    
    fileprivate func initScene(completion: @escaping (NSError?) -> Void) {
        
        SyncUtilsWrapper.initScene(uniqueId: uniqueId, sceneId: kSceneId) {[weak self] state, inited in
            guard let self = self else {
                return
            }
            
            defer {
                completion(state == .open ? nil : ShowError.networkError.toNSError())
            }
            
            if let _ = self.connectState {
                self.connectState = state
                return
            }
            self.connectState = state
            let showState = ShowServiceConnectState(rawValue: state.rawValue) ?? .open
            self.subscribeDelegate?.onConnectStateChanged(state: showState)            
            guard state == .open else { return }
            self._subscribeAll()
            guard !inited else {
                self._fetchCreatePkInvitation()
                self._getUserList {[weak self] (err, list) in
                    self?.subscribeDelegate?.onUserCountChanged(userCount: list?.count ?? 0)
                }
                return
            }
        }
    }
    
    private func cleanCache() {
        userList = [ShowUser]()
        messageList = [ShowMessage]()
        seatApplyList = [ShowMicSeatApply]()
//        seatInvitationList = [ShowMicSeatInvitation]()
        pkInvitationList = [ShowPKInvitation]()
        interactionList = [ShowInteractionInfo]()
        pkCreatedInvitationMap = [String: ShowPKInvitation]()
        userMuteLocalAudio = false
    }
    
    fileprivate func _checkRoomExpire() {
        guard let room = self.room else { return }
        
        let currentTs = Int64(Date().timeIntervalSince1970 * 1000)
        let expiredDuration = 20 * 60 * 1000
        agoraPrint("checkRoomExpire: \(currentTs - room.createdAt) / \(expiredDuration)")
        guard currentTs - room.createdAt > expiredDuration else { return }
        
        self.subscribeDelegate?.onRoomExpired()
    }
    
    fileprivate func _startCheckExpire() {
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            
            self._checkRoomExpire()
            if self.roomId == nil {
                timer.invalidate()
            }
        }
        
        DispatchQueue.main.async {
            self._checkRoomExpire()
        }
    }
    
    //MARK: ShowServiceProtocol
    func getRoomList(page: Int, completion: @escaping (NSError?, [ShowRoomListModel]?) -> Void) {
        _getRoomList(page: page) { [weak self] error, list in
            guard let self = self else { return }
            if let error = error {
                completion(error, nil)
                return
            }
            self.roomList = list
            completion(nil, list)
        }
    }
    
    @objc func createRoom(roomName: String,
                    roomId: String,
                    thumbnailId: String,
                    completion: @escaping (NSError?, ShowRoomDetailModel?) -> Void) {
        let room = ShowRoomListModel()
        room.roomName = roomName
        room.roomId = roomId
        room.thumbnailId = thumbnailId
        room.ownerId = VLUserCenter.user.id
        room.ownerName = VLUserCenter.user.name
        room.ownerAvatar = VLUserCenter.user.headUrl
        room.createdAt = Date().millionsecondSince1970()
        let params = room.yy_modelToJSONObject() as? [String: Any]
        initScene { [weak self] error in
            if let error = error  {
                completion(error, nil)
                return
            }
            SyncUtil.joinScene(id: room.roomId,
                          userId: room.ownerId,
                          isOwner: true,
                          property: params) { result in
                //            LogUtils.log(message: "result == \(result.toJson() ?? "")", level: .info)
                let channelName = result.getPropertyWith(key: "roomId", type: String.self) as? String
                guard let channelName = channelName else {
                    agoraAssert("createRoom fail: channelName == nil")
                    completion(nil, nil)
                    return
                }
                self?.roomId = channelName
                NetworkManager.shared.generateTokens(channelName: channelName,
                                                     uid: "\(UserInfo.userId)",
                                                     tokenGeneratorType: .token007,
                                                     tokenTypes: [.rtc]) { tokenMap in
                    guard let self = self,
                          let rtcToken = tokenMap[NetworkManager.AgoraTokenType.rtc.rawValue]
                    else {
                        agoraAssert(tokenMap.count == 2, "rtcToken == nil || rtmToken == nil")
                        return
                    }
                    var map = AppContext.shared.rtcTokenMap ?? [String: String]()
                    map[channelName] = rtcToken
                    AppContext.shared.rtcTokenMap = map
                    let output = ShowRoomDetailModel.yy_model(with: params!)
                    self.roomList?.append(room)
                    self._startCheckExpire()
                    self._subscribeAll()
//                    self._addUserIfNeed()
                    self._getAllPKInvitationList(room: nil) { error, list in
                    }
                    completion(nil, output)
                }
            } fail: { error in
                completion(error.toNSError(), nil)
            }
        }
    }
    
    @objc func joinRoom(room: ShowRoomListModel,
                        completion: @escaping (NSError?, ShowRoomDetailModel?) -> Void) {
        let params = room.yy_modelToJSONObject() as? [String: Any]
        initScene { [weak self] error in
            if let error = error  {
                completion(error, nil)
                return
            }
            SyncUtil.joinScene(id: room.roomId,
                                         userId: room.ownerId,
                                         isOwner: self?.isOwner(room) ?? false,
                                         property: params) { result in
                //            LogUtils.log(message: "result == \(result.toJson() ?? "")", level: .info)
                let channelName = result.getPropertyWith(key: "roomId", type: String.self) as? String
                guard let channelName = channelName else {
                    agoraAssert("joinRoom fail: channelName == nil")
                    completion(nil, nil)
                    return
                }
                self?.roomId = channelName
                NetworkManager.shared.generateTokens(channelName: channelName,
                                                     uid: "\(UserInfo.userId)",
                                                     tokenGeneratorType: .token007,
                                                     tokenTypes: [.rtc]) { tokenMap in
                    guard let self = self,
                          let rtcToken = tokenMap[NetworkManager.AgoraTokenType.rtc.rawValue]
                    else {
                        agoraAssert(tokenMap.count == 2, "rtcToken == nil || rtmToken == nil")
                        return
                    }
                    var map = AppContext.shared.rtcTokenMap ?? [String: String]()
                    map[channelName] = rtcToken
                    AppContext.shared.rtcTokenMap = map
                    let output = ShowRoomDetailModel.yy_model(with: params!)
                    completion(nil, output)
                    self._startCheckExpire()
                    self._subscribeAll()
//                    self._addUserIfNeed()
                    self._getAllPKInvitationList(room: nil) { error, list in
                    }
                }
            } fail: { error in
                completion(error.toNSError(), nil)
            }
        }
    }
    
    func leaveRoom(completion: @escaping (NSError?) -> Void) {
        defer {
            self.pkCreatedInvitationMap.values.forEach { invitation in
                let pkRoomId = invitation.roomId
                if pkRoomId.isEmpty {return}
                _leaveScene(roomId: pkRoomId)
            }
            
            cleanCache()
        }
        
        guard let roomInfo = roomList?.filter({ $0.roomId == self.getRoomId() }).first else {
//            agoraAssert("leaveRoom channelName = nil")
            completion(nil)
            return
        }
        _removeUser { err in
        }
        //current user is room owner, remove room
        if roomInfo.ownerId == VLUserCenter.user.id {
            //cancel pk invitation
            pkCreatedInvitationMap.values.forEach { invitation in
                self._removePKInvitation(invitation: invitation) { err in
                }
            }
            
            //remove pk if owner
            interactionList.forEach { interaction in
                guard interaction.interactStatus == .pking else {return}
                self.stopInteraction(interaction: interaction) { err in
                }
            }
            _removeRoom(completion: completion)
            return
        }
        
        cancelMicSeatApply { error in
        }
        
        //remove single interaction if audience
        interactionList.forEach { interaction in
            guard interaction.userId == VLUserCenter.user.id else {return}
            self.stopInteraction(interaction: interaction) { err in
            }
        }
        
        _leaveRoom(completion: completion)
    }
    
    func initRoom(completion: @escaping (NSError?) -> Void) {
        _addUserIfNeed(finished: completion)
    }
    
    func deinitRoom(completion: @escaping (NSError?) -> Void) {
        _removeUser(completion: completion)
    }
    
    func getAllUserList(completion: @escaping (NSError?, [ShowUser]?) -> Void) {
        _getUserList(finished: completion)
    }
    
    func sendChatMessage(message: ShowMessage, completion: ((NSError?) -> Void)?) {
        _addMessage(message: message, finished: completion)
    }
    
    func getAllMicSeatApplyList(completion: @escaping (NSError?, [ShowMicSeatApply]?) -> Void) {
        _getAllMicSeatApplyList(completion: completion)
    }
    
    
    func unsubscribeEvent(delegate: ShowSubscribeServiceProtocol) {
        //TODO: weak map
        self.subscribeDelegate = nil
    }
    
    func subscribeEvent(delegate: ShowSubscribeServiceProtocol) {
        //TODO: weak map
        self.subscribeDelegate = delegate
    }
    
    @objc func createMicSeatApply(completion: @escaping (NSError?) -> Void) {
        let apply = ShowMicSeatApply()
        apply.userId = VLUserCenter.user.id
        apply.userName = VLUserCenter.user.name
        apply.avatar = VLUserCenter.user.headUrl
        apply.createdAt = Int64(Date().timeIntervalSince1970 * 1000)
        apply.status = .waitting
        _addMicSeatApply(apply: apply, completion: completion)
    }
    
    func cancelMicSeatApply(completion: @escaping (NSError?) -> Void) {
        // 房主移除所有accept
        if room?.ownerId == VLUserCenter.user.id {
            self.seatApplyList.forEach { apply in
                if apply.status == .accepted {
                    _removeMicSeatApply(apply: apply, completion: completion)
                }
            }
            return
        }
  
        guard let apply = self.seatApplyList.filter({ $0.userId == VLUserCenter.user.id }).first else {
//            agoraAssert("cancel apply not found")
            return
        }
        _removeMicSeatApply(apply: apply, completion: completion)
    }
    
    func acceptMicSeatApply(apply: ShowMicSeatApply, completion: @escaping (NSError?) -> Void) {
        apply.status = .accepted
        _updateMicSeatApply(apply: apply, completion: completion)
        
        
        //reset mute status if start interaction
        self.userMuteLocalAudio = false
        
        let interaction = ShowInteractionInfo()
        interaction.userId = apply.userId
        interaction.userName = apply.userName
        interaction.roomId = getRoomId()
        interaction.interactStatus = .onSeat
//        interaction.ownerMuteAudio = self.userMuteLocalAudio
        interaction.createdAt = Int64(Date().timeIntervalSince1970 * 1000)
        _addInteraction(interaction: interaction) { error in
        }
    }
    
    func rejectMicSeatApply(apply: ShowMicSeatApply, completion: @escaping (NSError?) -> Void) {
        apply.status = .rejected
        _updateMicSeatApply(apply: apply, completion: completion)
    }
    
    func getAllMicSeatInvitationList(completion: @escaping (NSError?, [ShowMicSeatInvitation]?) -> Void) {
//        _getAllMicSeatInvitationList(completion: completion)
        _getUserList(finished: completion)
    }
    
    func createMicSeatInvitation(user: ShowUser, completion: @escaping (NSError?) -> Void) {
        //check interaction maximum
        if self.interactionList.count > 0 {
            completion(ShowError.seatInteractionMaximumReach.toNSError())
            return
        }
        
        user.status = .waitting
//        _addMicSeatInvitation(invitation: user, completion: completion)
        _updateUserInfo(user: user, completion: completion)
    }
    
    func cancelMicSeatInvitation(userId: String, completion: @escaping (NSError?) -> Void) {
//        guard let invitation = self.seatInvitationList.filter({ $0.userId == userId }).first else {
////            agoraAssert("cancel invitation not found")
//            return
//        }
//
//        _removeMicSeatInvitation(invitation: invitation, completion: completion)
        guard let user = self.userList.filter({ $0.userId == userId }).first else { return }
        user.status = .idle
        _updateUserInfo(user: user, completion: completion)
    }
    
    func acceptMicSeatInvitation(completion: @escaping (NSError?) -> Void) {
//        guard let invitation = self.seatInvitationList.filter({ $0.userId == VLUserCenter.user.userNo }).first else {
//            agoraAssert("accept invitation not found")
//            return
//        }
//        invitation.status = .accepted
//        _updateMicSeatInvitation(invitation: invitation, completion: completion)
        _getUserList { [weak self] (error, userList) in
            guard let self = self else { return }
            guard let user = self.userList.filter({ $0.userId == VLUserCenter.user.id }).first else {
                agoraAssert("accept invitation not found")
                return
            }
            user.status = .accepted
            self._updateUserInfo(user: user, completion: completion)
            
            //reset mute status if start interaction
            self.userMuteLocalAudio = false

            let interaction = ShowInteractionInfo()
            interaction.userId = user.userId
            interaction.userName = user.userName
            interaction.roomId = self.getRoomId()
            interaction.interactStatus = .onSeat
//            interaction.muteAudio = self.userMuteLocalAudio
            interaction.createdAt = Int64(Date().timeIntervalSince1970 * 1000)
            self._addInteraction(interaction: interaction) { error in
            }
        }
    }
    
    func rejectMicSeatInvitation(completion: @escaping (NSError?) -> Void) {
//        guard let invitation = self.seatInvitationList.filter({ $0.userId == VLUserCenter.user.userNo }).first else {
//            agoraAssert("reject invitation not found")
//            return
//        }
//        invitation.status = .rejected
//        _updateMicSeatInvitation(invitation: invitation, completion: completion)
        _getUserList { [weak self] (error, userList) in
            guard let self = self else { return }
            guard let user = self.userList.filter({ $0.userId == VLUserCenter.user.id }).first else {
                agoraAssert("reject invitation not found")
                return
            }
            user.status = .rejected
            self._updateUserInfo(user: user, completion: completion)
        }
    }
    
    
    func getAllPKUserList(completion: @escaping (NSError?, [ShowPKUserInfo]?) -> Void) {
        _getRoomList(page: 0) { [weak self] (error, list) in
            guard let self = self else {
                return
            }
            if let err = error {
                completion(err, nil)
                return
            }
            self.roomList = list
            let filterList = list?.filter({ $0.ownerId != VLUserCenter.user.id })
            completion(nil, filterList)
        }
    }
    
    func getAllPKInvitationList(completion: @escaping (NSError?, [ShowPKInvitation]?) -> Void) {
        _getAllPKInvitationList(room: nil, completion: completion)
    }
    
    func getCurrentApplyUser(roomId: String?, completion: @escaping (ShowRoomListModel?) -> Void) {
        _getCurrentApplyUser(roomId: roomId, completion: completion)
    }
    
    func createPKInvitation(room: ShowRoomListModel,
                            completion: @escaping (NSError?) -> Void) {
        //if robot room, reject
        if room.roomId.count > 6 {
            completion(ShowError.userCannotAccept.toNSError())
            return
        }
        
        //check interaction maximum
        if self.interactionList.count > 0 {
            completion(ShowError.pkInteractionMaximumReach.toNSError())
            return
        }
        
        agoraPrint("imp pk invitation create")
        self.createPkInvitationClosure = completion
        _getAllPKInvitationList(room: room) {[weak self] error, invitationList in
            guard let self = self, error == nil, let invitationList = invitationList else { return }
            
            self._unsubscribePKInvitationChanged(roomId: room.roomId)
            self._subscribePKInvitationChanged(channelName: room.roomId) {[weak self] (status, invitation) in
                self?._handleCreatePkInvitationRespone(invitation: invitation, status: status)
            }
            
            guard let completion = self.createPkInvitationClosure else {
                //TODO: remove pk invitation alway callback
                agoraPrint("createPkInvitation fail")
                return
            }
            self.createPkInvitationClosure = nil
            guard let invitation = invitationList.filter({ $0.fromRoomId == self.roomId }).first else {
                //not found, add invitation
                let _invitation = ShowPKInvitation()
                _invitation.userId = room.ownerId
                _invitation.userName = room.ownerName
                _invitation.roomId = room.roomId
                _invitation.fromUserId = VLUserCenter.user.id
                _invitation.fromName = VLUserCenter.user.name
                _invitation.fromRoomId = self.roomId ?? ""
                _invitation.status = .waitting
//                _invitation.fromUserMuteAudio = self.userMuteLocalAudio
                _invitation.createdAt = Int64(Date().timeIntervalSince1970 * 1000)
                self.pkCreatedInvitationMap[_invitation.roomId] = _invitation
                self._addPKInvitation(invitation: _invitation, completion: completion)
                return
            }
            
            self.pkCreatedInvitationMap[invitation.roomId] = invitation
//            if invitation.status == .waitting {
//                agoraPrint("pk invitaion already send ")
//                return
//            }
            
            invitation.status = .waitting
            invitation.createdAt = Int64(Date().timeIntervalSince1970 * 1000)
            //found, update invitation
            self._updatePKInvitation(invitation: invitation, completion: completion)
        }
    }
    
    func acceptPKInvitation(completion: @escaping (NSError?) -> Void) {
        guard let room = room else { return }
        _getAllPKInvitationList(room: room) { [weak self] (error, list) in
            guard let self = self,
                  let list = list,
                  let invitation = list.filter({ $0.userId == VLUserCenter.user.id }).first else {
                agoraPrint("accept invitation not found")
                return
            }
            
            
            //reset mute status if start interaction
            self.userMuteLocalAudio = false
            
            invitation.status = .accepted
            invitation.userMuteAudio = self.userMuteLocalAudio
            self._updatePKInvitation(invitation: invitation, completion: completion)
            
            let interaction = ShowInteractionInfo()
            interaction.userId = invitation.fromUserId
            interaction.userName = invitation.fromName
            interaction.roomId = invitation.fromRoomId
//            interaction.muteAudio = invitation.fromUserMuteAudio
//            interaction.ownerMuteAudio = self.userMuteLocalAudio
            interaction.interactStatus = .pking
            interaction.createdAt = Int64(Date().timeIntervalSince1970 * 1000)
            self._addInteraction(interaction: interaction) { error in
            }
        }
    }
    
    func rejectPKInvitation(completion: @escaping (NSError?) -> Void) {
        guard let room = room else { return }
        _getAllPKInvitationList(room: room) { [weak self] (error, list) in
            guard let self = self,
                  let list = list,
                  let invitation = list.filter({ $0.userId == VLUserCenter.user.id }).first else {
                agoraPrint("accept invitation not found")
                return
            }
            self._removePKInvitation(invitation: invitation, completion: completion)
        }
    }
    
    func getAllInterationList(completion: @escaping (NSError?, [ShowInteractionInfo]?) -> Void) {
//        interactionPaddingIdsSet.removeAll()
        _getAllInteractionList(completion: completion)
    }
    
    func stopInteraction(interaction: ShowInteractionInfo, completion: @escaping (NSError?) -> Void) {
        _removeInteraction(interaction: interaction, completion: completion)
        guard interaction.interactStatus == .pking else {
            // seat apply / interation
            cancelMicSeatApply { error in
            }
            
            cancelMicSeatInvitation(userId: interaction.userId) { err in
            }
            return
        }
        
        // pk invitation sender
        if let invitation = self.pkCreatedInvitationMap.values.filter({ $0.roomId == interaction.roomId }).first {
//            invitation.status = .ended
//            _updatePKInvitation(invitation: invitation, completion: completion)
//            _unsubscribePKInvitationChanged(roomId: invitation.roomId)
            _removePKInvitation(invitation: invitation, completion: completion)
            return
        }
        
        // pk invitation recviver
        _getAllPKInvitationList(room: nil) {[weak self] (error, list) in
            guard let self = self,
                  let pkList = list,
                  let invitation = pkList.filter({$0.fromUserId == interaction.userId }).first else {
//                agoraAssert("stopInteraction not found invitation: \(interaction.userId ?? "") \(interaction.roomId ?? "")")
                return
            }
    //        invitation.status = .ended
    //        _updatePKInvitation(invitation: invitation, completion: completion)
            self._removePKInvitation(invitation: invitation, completion: completion)
        }
    }
    
    
    func muteAudio(mute:Bool, userId: String, completion: @escaping (NSError?) -> Void) {
        let isCurrentUser = userId == VLUserCenter.user.id ? true : false
        if isCurrentUser {
            self.userMuteLocalAudio = mute
        }
        if let interaction = self.interactionList.first,
            interaction.interactStatus == .onSeat {
            let isRoomOwner = VLUserCenter.user.id == room?.ownerId ? true : false
            //is on seat
            if interaction.userId == userId {
                interaction.muteAudio = mute
            } else {
                if isRoomOwner, isCurrentUser {
                    interaction.ownerMuteAudio = mute
                } else {
                    agoraPrint("other co-mic interaction")
                    return
                }
            }
            
            _updateInteraction(interaction: interaction) { err in
            }
        }
        
        guard let pkInvitation = self.pkCreatedInvitationMap.values.filter({ $0.status == .accepted}).first else {
            // pk recviver
            _getAllPKInvitationList(room: nil) {[weak self] (error, list) in
                guard let invitation = list?.filter({ $0.status == .accepted }).first else { return }
                if isCurrentUser {
                    invitation.userMuteAudio = mute
                } else {
                    invitation.fromUserMuteAudio = mute
                }
                self?._updatePKInvitation(invitation: invitation) { err in
                }
            }
            return
        }
        
        //is pk, send mute status (pk sender)
        if isCurrentUser {
            pkInvitation.fromUserMuteAudio = mute
        } else {
            pkInvitation.userMuteAudio = mute
        }
        _updatePKInvitation(invitation: pkInvitation) { err in
        }
    }
}


//MARK: room operation
extension ShowSyncManagerServiceImp {
    @objc func _getRoomList(page: Int, completion: @escaping (NSError?, [ShowRoomListModel]?) -> Void) {
        initScene { error in
            if let error = error {
                completion(error, nil)
                return
            }
            SyncUtil.fetchAll { results in
                agoraPrint("result == \(results.compactMap { $0.toJson() })")
                let dataArray = results.map({ info in
                    return ShowRoomListModel.yy_model(with: info.toJson()!.toDictionary())!
                })
                let roomList = dataArray.sorted(by: { ($0.updatedAt > 0 ? $0.updatedAt : $0.createdAt) > ($1.updatedAt > 0 ? $1.updatedAt : $1.createdAt) })
                completion(nil, roomList)
            } fail: { error in
                completion(error.toNSError(), nil)
            }
        }
    }
    
    
    private func _updateRoomInteractionStatus(status: ShowInteractionStatus) {
        guard let channelName = roomId,
              let roomInfo = roomList?.filter({ $0.roomId == roomId }).first,
              roomInfo.ownerId == VLUserCenter.user.id
        else {
//            assert(false, "channelName = nil")
            agoraPrint("_updateRoomRequestStatus channelName = nil")
            return
        }
        roomInfo.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        roomInfo.interactStatus = status
        var params = roomInfo.yy_modelToJSONObject() as! [String: Any]
        let objectId = channelName
        agoraPrint("imp room update status... [\(objectId)]")
        params["objectId"] = objectId
        SyncUtil
            .scene(id: channelName)?
            .update(key: "",
                    data: params,
                    success: { obj in
                agoraPrint("imp room update status success...")
            }, fail: { error in
                agoraPrint("imp room update status fail \(error.message)...")
            })
    }
    
    private func _leaveRoom(completion: @escaping (NSError?) -> Void) {
        defer {
            _unsubscribeAll()
            roomId = nil
            completion(nil)
        }
        
        guard let channelName = roomId else {
            agoraAssert("channelName = nil")
            return
        }
        _removeUser { error in
        }
        
        _leaveScene(roomId: channelName)
    }

    private func _removeRoom(completion: @escaping (NSError?) -> Void) {
        guard let channelName = roomId else {
            agoraAssert("channelName = nil")
            return
        }
        SyncUtil.scene(id: channelName)?.deleteScenes()
        roomId = nil
        completion(nil)
    }
    
    fileprivate func _subscribeAll() {
        agoraPrint("imp all subscribe...")
        _subscribeOnlineUsersChanged()
        _subscribeMessageChanged()
        _subscribeMicSeatApplyChanged()
        _subscribeInteractionChanged()
        guard room?.ownerId == VLUserCenter.user.id else { return }
        _subscribePKInvitationChanged()
    }
    
    private func _unsubscribeAll() {
        guard let channelName = roomId else {
            return
        }
        agoraPrint("imp all unsubscribe...")
        SyncUtil
            .scene(id: channelName)?
            .unsubscribeScene()
    }
    
    private func _leaveScene(roomId: String) {
        agoraPrint("imp leave scene: \(roomId)")
        SyncUtil.leaveScene(id: roomId)
    }
}

//MARK: user operation
extension ShowSyncManagerServiceImp {
    fileprivate func _addUserIfNeed(finished: @escaping (NSError?) -> Void) {
        _getUserList {[weak self] error, userList in
            guard let self = self else {
                finished(NSError(domain: "unknown error", code: -1))
                return
            }
            // current user already add
            if self.userList.contains(where: { $0.userId == VLUserCenter.user.id }) {
                finished(nil)
                return
            }
            self._addUserInfo {
                finished(nil)
            }
        }
    }

    private func _getUserList(finished: @escaping (NSError?, [ShowUser]?) -> Void) {
        guard let channelName = roomId else {
//            agoraAssert("channelName = nil")
            return
        }
        agoraPrint("imp user get...")
        SyncUtil
            .scene(id: channelName)?
            .collection(className: SYNC_SCENE_ROOM_USER_COLLECTION)
            .get(success: { [weak self] list in
                agoraPrint("imp user get success...")
                let users = list.compactMap({ ShowUser.yy_model(withJSON: $0.toJson()!)! })
//            guard !users.isEmpty else { return }
                self?.userList = users
                self?._updateUserCount(completion: { error in

                })
                finished(nil, users)
            }, fail: { error in
                agoraPrint("imp user get fail :\(error.message)...")
                finished(error.toNSError(), nil)
            })
    }

    private func _addUserInfo(finished: @escaping () -> Void) {
        guard let channelName = roomId else {
//            assert(false, "channelName = nil")
            print("addUserInfo channelName = nil")
            return
        }
        let model = ShowUser()
        model.userId = VLUserCenter.user.id
        model.avatar = VLUserCenter.user.headUrl
        model.userName = VLUserCenter.user.name

        let params = model.yy_modelToJSONObject() as! [String: Any]
        agoraPrint("imp user add ...")
        SyncUtil
            .scene(id: channelName)?
            .collection(className: SYNC_SCENE_ROOM_USER_COLLECTION)
            .add(data: params, success: { [weak self] object in
                agoraPrint("imp user add success...")
                guard let self = self,
                      let jsonStr = object.toJson(),
                      let model = ShowUser.yy_model(withJSON: jsonStr) else {
                    return
                }
                
                if self.userList.contains(where: { $0.userId == model.userId }) {
                    return
                }
                
                self.userList.append(model)
                finished()
            }, fail: { error in
                agoraPrint("imp user add fail :\(error.message)...")
                finished()
            })
    }
    
    
    private func _updateUserInfo(user: ShowUser, completion: @escaping (NSError?) -> Void) {
        let channelName = getRoomId()
        agoraPrint("imp user update...")

        let params = user.yy_modelToJSONObject() as! [String: Any]
        SyncUtil
            .scene(id: channelName)?
            .collection(className: SYNC_SCENE_ROOM_USER_COLLECTION)
            .update(id: user.objectId!,
                    data:params,
                    success: {
                agoraPrint("imp user update success...")
                completion(nil)
            }, fail: { error in
                agoraPrint("imp user update fail :\(error.message)...")
                completion(error.toNSError())
            })
    }

    private func _subscribeOnlineUsersChanged() {
        guard let channelName = roomId else {
            agoraAssert("channelName = nil")
            return
        }
        agoraPrint("imp user subscribe ...")
        SyncUtil
            .scene(id: channelName)?
            .subscribe(key: SYNC_SCENE_ROOM_USER_COLLECTION,
                       onCreated: { _ in
                       }, onUpdated: { [weak self] object in
                           agoraPrint("imp user subscribe onUpdated...")
                           guard let self = self,
                                 let jsonStr = object.toJson(),
                                 let model = ShowUser.yy_model(withJSON: jsonStr) else { return }
                           defer{
                               self._updateUserCount { error in
                               }
                               self.subscribeDelegate?.onUserCountChanged(userCount: self.userList.count)
                           }
                           if self.userList.contains(where: { $0.userId == model.userId }) {
                               self.subscribeDelegate?.onMicSeatInvitationUpdated(invitation: model)
                               return
                           }
                           self.userList.append(model)
                           self.subscribeDelegate?.onUserJoinedRoom(user: model)
                           self.subscribeDelegate?.onUserCountChanged(userCount: self.userList.count)
                           
                       }, onDeleted: { [weak self] object in
                           agoraPrint("imp user subscribe onDeleted... [\(object.getId())]")
                           guard let self = self else { return }
                           var model: ShowUser? = nil
                           if let index = self.userList.firstIndex(where: { object.getId() == $0.objectId }) {
                               model = self.userList[index]
                               self.userList.remove(at: index)
                               self._updateUserCount { error in
                               }
                               guard let model = model else { return }
                               self.subscribeDelegate?.onMicSeatInvitationDeleted(invitation: model)
                           }
                           guard let model = model else { return }
                           self.subscribeDelegate?.onUserLeftRoom(user: model)
                           self.subscribeDelegate?.onUserCountChanged(userCount: self.userList.count)
                       }, onSubscribed: {
//                LogUtils.log(message: "subscribe message", level: .info)
                       }, fail: { error in
                           agoraPrint("imp user subscribe fail \(error.message)...")
                           ToastView.show(text: error.message)
                       })
    }

    private func _removeUser(completion: @escaping (NSError?) -> Void) {
        guard let channelName = roomId else {
            agoraAssert("channelName = nil")
            return
        }
        
        guard let objectId = userList.filter({ $0.userId == VLUserCenter.user.id }).first?.objectId else {
            agoraPrint("_removeUser objectId = nil")
            return
        }
        agoraPrint("imp user delete... [\(objectId)]")
        SyncUtil
            .scene(id: channelName)?
            .collection(className: SYNC_SCENE_ROOM_USER_COLLECTION)
            .delete(id: objectId,
                    success: { _ in
                agoraPrint("imp user delete success...")
            }, fail: { error in
                agoraPrint("imp user delete fail \(error.message)...")
                completion(error.toNSError())
            })
    }

    private func _updateUserCount(completion: @escaping (NSError?) -> Void) {
        _updateUserCount(with: userList.count)
    }

    private func _updateUserCount(with count: Int) {
        guard let channelName = roomId,
              let roomInfo = roomList?.filter({ $0.roomId == self.getRoomId() }).first,
              roomInfo.ownerId == VLUserCenter.user.id
        else {
//            agoraPrint("updateUserCount channelName = nil")
//            userListCountDidChanged?(UInt(count))
            return
        }
        let roomUserCount = count
        if roomUserCount == roomInfo.roomUserCount {
            return
        }
        roomInfo.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        roomInfo.roomUserCount = roomUserCount
        roomInfo.objectId = channelName
        let params = roomInfo.yy_modelToJSONObject() as! [String: Any]
        agoraPrint("imp room update user count... [\(channelName)]")
        SyncUtil
            .scene(id: channelName)?
            .update(key: "",
                    data: params,
                    success: { obj in
                agoraPrint("imp room update user count success...")
            }, fail: { error in
                agoraPrint("imp room update user count fail \(error.message)...")
            })

//        userListCountDidChanged?(UInt(count))
    }
    
    private func _updateInteractionStatus(with status: ShowInteractionStatus) {
        guard let channelName = roomId,
              let roomInfo = roomList?.filter({ $0.roomId == self.getRoomId() }).first,
              roomInfo.ownerId == VLUserCenter.user.id
        else {
//            agoraPrint("updateUserCount channelName = nil")
//            userListCountDidChanged?(UInt(count))
            return
        }
        roomInfo.updatedAt = Int64(Date().timeIntervalSince1970 * 1000)
        roomInfo.interactStatus = status
        roomInfo.objectId = channelName
        let params = roomInfo.yy_modelToJSONObject() as! [String: Any]
        agoraPrint("imp room update interaction status... \(channelName)")
        SyncUtil
            .scene(id: channelName)?
            .update(key: "",
                    data: params,
                    success: { obj in
                agoraPrint("imp room update interaction status success... \(channelName)")
            }, fail: { error in
                agoraPrint("imp room update interaction status fail \(error.message)... \(channelName)")
            })

//        userListCountDidChanged?(UInt(count))
    }
}


//MARK: message operation
extension ShowSyncManagerServiceImp {
    private func _getMessageList(finished: @escaping (NSError?, [ShowMessage]?) -> Void) {
        let channelName = getRoomId()
        agoraPrint("imp message get...")
        SyncUtil
            .scene(id: channelName)?
            .collection(className: SYNC_MANAGER_MESSAGE_COLLECTION)
            .get(success: { [weak self] list in
                agoraPrint("imp user get success...")
                let messageList = list.compactMap({ ShowMessage.yy_model(withJSON: $0.toJson()!)! })
//            guard !users.isEmpty else { return }
                self?.messageList = messageList
                finished(nil, messageList)
            }, fail: { error in
                agoraPrint("imp user get fail :\(error.message)...")
                agoraPrint("error = \(error.description)")
                finished(error.toNSError(), nil)
            })
    }

    private func _addMessage(message:ShowMessage, finished: ((NSError?) -> Void)?) {
        let channelName = getRoomId()
        agoraPrint("imp message add ...")

        let params = message.yy_modelToJSONObject() as! [String: Any]
        SyncUtil
            .scene(id: channelName)?
            .collection(className: SYNC_MANAGER_MESSAGE_COLLECTION)
            .add(data: params, success: { object in
                agoraPrint("imp message add success...\(channelName) params = \(params)")
                finished?(nil)
            }, fail: { error in
                agoraPrint("imp message add fail :\(error.message)...\(channelName)")
                agoraPrint(error.message)
                finished?(error.toNSError())
            })
    }

    private func _subscribeMessageChanged() {
        let channelName = getRoomId()
        agoraPrint("imp message subscribe ...")
        SyncUtil
            .scene(id: channelName)?
            .subscribe(key: SYNC_MANAGER_MESSAGE_COLLECTION,
                       onCreated: { _ in
                       }, onUpdated: {[weak self] object in
                           agoraPrint("imp message subscribe onUpdated... [\(object.getId())] \(channelName)")
                           guard let self = self,
                                 let jsonStr = object.toJson(),
                                 let model = ShowMessage.yy_model(withJSON: jsonStr)
                           else {
                               return
                           }
                           self.messageList.append(model)
                           self.subscribeDelegate?.onMessageDidAdded(message: model)
                       }, onDeleted: { object in
                           agoraPrint("imp message subscribe onDeleted... [\(object.getId())] \(channelName)")
                           agoraAssert("not implemented")
                       }, onSubscribed: {
                       }, fail: { error in
                           agoraPrint("imp message subscribe fail \(error.message)...")
                           ToastView.show(text: error.message)
                       })
    }
}

//MARK: Seat Apply
extension ShowSyncManagerServiceImp {
    private func _getAllMicSeatApplyList(completion: @escaping (NSError?, [ShowMicSeatApply]?) -> Void) {
        let channelName = getRoomId()
        agoraPrint("imp seat apply get...")
        SyncUtil
            .scene(id: channelName)?
            .collection(className: SYNC_MANAGER_SEAT_APPLY_COLLECTION)
            .get(success: { [weak self] list in
                agoraPrint("imp seat apply get success... \(list.count)")
                let seatApplyList = list.compactMap({ ShowMicSeatApply.yy_model(withJSON: $0.toJson()!)! })
                self?.seatApplyList = seatApplyList
                completion(nil, seatApplyList)
            }, fail: { error in
                agoraPrint("imp seat apply get fail :\(error.message)...")
                completion(error.toNSError(), nil)
            })
    }
    
    private func _subscribeMicSeatApplyChanged() {
        let channelName = getRoomId()
        agoraPrint("imp seat apply subscribe ...")
        SyncUtil
            .scene(id: channelName)?
            .subscribe(key: SYNC_MANAGER_SEAT_APPLY_COLLECTION,
                       onCreated: { _ in
                       }, onUpdated: {[weak self] object in
                           agoraPrint("imp seat apply subscribe onUpdated...")
                           guard let self = self,
                                 let jsonStr = object.toJson(),
                                 let model = ShowMicSeatApply.yy_model(withJSON: jsonStr) else { return }
                           defer {
                               self.subscribeDelegate?.onMicSeatApplyUpdated(apply: model)
                           }
                           if self.seatApplyList.contains(where: { $0.userId == model.userId }) { return }
                           self.seatApplyList.append(model)
                       }, onDeleted: {[weak self] object in
                           agoraPrint("imp seat apply subscribe onDeleted...")
                           guard let self = self else {return}
                           var model: ShowMicSeatApply? = nil
                           if let index = self.seatApplyList.firstIndex(where: { object.getId() == $0.objectId }) {
                               model = self.seatApplyList[index]
                               self.seatApplyList.remove(at: index)
                           }
                           guard let model = model else {return}
                           self.subscribeDelegate?.onMicSeatApplyDeleted(apply: model)
                       }, onSubscribed: {
                       }, fail: { error in
                           agoraPrint("imp seat apply subscribe fail \(error.message)...")
                           ToastView.show(text: error.message)
                       })
    }
    
    private func _addMicSeatApply(apply: ShowMicSeatApply, completion: @escaping (NSError?) -> Void) {
        let channelName = getRoomId()
        agoraPrint("imp seat apply add ...")

        let params = apply.yy_modelToJSONObject() as! [String: Any]
        SyncUtil
            .scene(id: channelName)?
            .collection(className: SYNC_MANAGER_SEAT_APPLY_COLLECTION)
            .add(data: params, success: { object in
                agoraPrint("imp seat apply add success...")
                completion(nil)
            }, fail: { error in
                agoraPrint("imp seat apply add fail :\(error.message)...")
                completion(error.toNSError())
            })
    }
    
    private func _removeMicSeatApply(apply: ShowMicSeatApply, completion: @escaping (NSError?) -> Void) {
        let channelName = getRoomId()
        agoraPrint("imp seat apply remove...")

        SyncUtil
            .scene(id: channelName)?
            .collection(className: SYNC_MANAGER_SEAT_APPLY_COLLECTION)
            .delete(id: apply.objectId!,
                    success: { _ in
                agoraPrint("imp seat apply remove success...")
                completion(nil)
            }, fail: { error in
                agoraPrint("imp seat apply remove fail :\(error.message)...")
                completion(error.toNSError())
            })
    }
    
    private func _updateMicSeatApply(apply: ShowMicSeatApply, completion: @escaping (NSError?) -> Void) {
        let channelName = getRoomId()
        agoraPrint("imp seat apply update...")

        let params = apply.yy_modelToJSONObject() as! [String: Any]
        SyncUtil
            .scene(id: channelName)?
            .collection(className: SYNC_MANAGER_SEAT_APPLY_COLLECTION)
            .update(id: apply.objectId!,
                    data:params,
                    success: {
                agoraPrint("imp seat apply update success...")
                completion(nil)
            }, fail: { error in
                agoraPrint("imp seat apply update fail :\(error.message)...")
                completion(error.toNSError())
            })
    }
}


//MARK: PK Invitation
extension ShowSyncManagerServiceImp {
    fileprivate func _getAllPKInvitationList(room: ShowRoomListModel?,
                                         completion: @escaping (NSError?, [ShowPKInvitation]?) -> Void) {
        guard let channelName = room?.roomId ?? roomId else {
            agoraAssert("channelName = nil")
            return
        }
        
        //get another room pk invitation list
        if roomId != channelName {
            guard let params = room?.yy_modelToJSONObject() as? [String: Any], let ownerId = room?.ownerId else {
                agoraAssert("room convert to param fail")
                return
            }
            
            agoraPrint("imp pk invitation get2... \(channelName)")
            SyncUtil.joinScene(id: channelName,
                               userId: ownerId,
                               isOwner: true,
                               property: params) { result in
                SyncUtil
                    .scene(id: channelName)?
                    .collection(className: SYNC_MANAGER_PK_INVITATION_COLLECTION)
                    .get(success: {  list in
                        agoraPrint("imp pk invitation get2 success...  \(channelName)")
                        let pkInvitationList = list.compactMap({ ShowPKInvitation.yy_model(withJSON: $0.toJson()!)! })
                        completion(nil, pkInvitationList)
                    }, fail: { error in
                        agoraPrint("imp pk invitation get2 fail :\(error.message)... \(channelName)")
                        completion(error.toNSError(), nil)
                    })
            } fail: { error in
                completion(error.toNSError(), nil)
            }
            return
        }
        
        agoraPrint("imp pk invitation get... \(channelName)")
        SyncUtil
            .scene(id: channelName)?
            .collection(className: SYNC_MANAGER_PK_INVITATION_COLLECTION)
            .get(success: { [weak self] list in
                agoraPrint("imp pk invitation get success...")
                let pkInvitationList = list.compactMap({ ShowPKInvitation.yy_model(withJSON: $0.toJson()!)! })
                self?.pkInvitationList = pkInvitationList
                completion(nil, pkInvitationList)
            }, fail: { error in
                agoraPrint("imp pk invitation get fail :\(error.message)...")
                completion(error.toNSError(), nil)
            })
        
    }
    
    private func _unsubscribePKInvitationChanged(roomId:String?) {
        guard let channelName = roomId else {
            agoraAssert("channelName = nil")
            return
        }
        agoraPrint("imp pk invitation unsubscribe ...")
        SyncUtil
            .scene(id: channelName)?
            .unsubscribe(key: SYNC_MANAGER_PK_INVITATION_COLLECTION)
    }
    
    private func _subscribePKInvitationChanged() {
        guard let channelName = roomId else {
            agoraAssert("channelName = nil")
            return
        }
        agoraPrint("imp pk invitation subscribe ...")
        _subscribePKInvitationChanged(channelName: channelName) { [weak self] (status, invitation) in
            guard let self = self else { return }
            switch status {
            case .deleted:
                var model: ShowPKInvitation? = nil
                if let index = self.pkInvitationList.firstIndex(where: { invitation.objectId == $0.objectId }) {
                    model = self.pkInvitationList[index]
                    self.pkInvitationList.remove(at: index)
                }
                let _invitation = model ?? invitation
                
                self.subscribeDelegate?.onPKInvitationRejected(invitation: _invitation)
                self._removeInteraction(invitation: _invitation) { error in
                }
                self._updateRoomInteractionStatus(status: .idle)
            case .updated:
                let pkInteraction = self.interactionList.filter({ $0.userId == invitation.fromUserId}).first
                let pkInvitation = self.pkInvitationList.filter({$0.objectId == invitation.objectId}).first
                
                //can not invitation if interaction already exist
                if self.interactionList.count > 0, pkInteraction == nil {
                    self._removeInteraction(invitation: invitation) { err in
                    }
                    return
                }
                
                //update invitation (mute audio)
                if let pkInvitation = pkInvitation {
                    pkInvitation.fromUserMuteAudio = invitation.fromUserMuteAudio
                } else {
                    self.pkInvitationList.append(invitation)
                }
                
                //update interaction
                if let pkInteraction = pkInteraction {
                    //update interaction
                    pkInteraction.muteAudio = invitation.fromUserMuteAudio
                    pkInteraction.ownerMuteAudio = invitation.userMuteAudio
                    self._updateInteraction(interaction: pkInteraction) { err in
                    }
                }
                
                if invitation.status == .accepted {
                    self.subscribeDelegate?.onPKInvitationAccepted(invitation: invitation)
                } else if invitation.status == .rejected {
                    self.subscribeDelegate?.onPKInvitationRejected(invitation: invitation)
                } else {
                    self.subscribeDelegate?.onPKInvitationUpdated(invitation: invitation)
                }
                
            default:
                break
            }
        }
    }
    
    private func _subscribePKInvitationChanged(channelName:String,
                                               subscribeClosure: @escaping (ShowSubscribeStatus, ShowPKInvitation) -> Void) {
        agoraPrint("imp pk invitation subscribe ... \(channelName)")
        SyncUtil
            .scene(id: channelName)?
            .subscribe(key: SYNC_MANAGER_PK_INVITATION_COLLECTION,
                       onCreated: { object in
                agoraPrint("imp pk invitation subscribe onCreated... \(channelName)")
                guard let jsonStr = object.toJson(),
                      let model = ShowPKInvitation.yy_model(withJSON: jsonStr) else {
                    return
                }
                subscribeClosure(.created, model)
            }, onUpdated: { object in
                agoraPrint("imp pk invitation subscribe onUpdated... \(channelName)")
                guard let jsonStr = object.toJson(),
                      let model = ShowPKInvitation.yy_model(withJSON: jsonStr) else {
                    return
                }
                subscribeClosure(.updated, model)
            }, onDeleted: {[weak self] object in
                agoraPrint("imp pk invitation subscribe onDeleted... \(channelName)")
                guard let self = self else {return}
                guard channelName == self.roomId else {
                    if let model = ShowPKInvitation.yy_model(withJSON: object.toJson() ?? "") {
                        subscribeClosure(.deleted, model)
                    } else {
                        agoraAssert("imp pk invitation subscribe fail")
                    }
                    return
                }
                guard let model = ShowPKInvitation.yy_model(withJSON: object.toJson() ?? "") else { return }
                subscribeClosure(.deleted, model)
            }, onSubscribed: {
            }, fail: { error in
                agoraPrint("imp pk invitation subscribe fail \(error.message)...")
                ToastView.show(text: error.message)
            })
    }
    
    private func _addPKInvitation(invitation: ShowPKInvitation, completion: @escaping (NSError?) -> Void) {
        let channelName = invitation.roomId
        if channelName.isEmpty {return}
        agoraPrint("imp pk invitation add... \(channelName)")

        let params = invitation.yy_modelToJSONObject() as! [String: Any]
        SyncUtil
            .scene(id: channelName)?
            .collection(className: SYNC_MANAGER_PK_INVITATION_COLLECTION)
            .add(data: params, success: { object in
                agoraPrint("imp pk invitation add success... \(channelName)")
                completion(nil)
            }, fail: { error in
                agoraPrint("imp pk invitation add fail :\(error.message)... \(channelName)")
                completion(error.toNSError())
            })
    }
    
    private func _removePKInvitation(invitation: ShowPKInvitation, completion: @escaping (NSError?) -> Void) {
        let channelName = invitation.roomId
        if channelName.isEmpty {return}
        agoraPrint("imp pk invitation remove... \(channelName)")

        SyncUtil
            .scene(id: channelName)?
            .collection(className: SYNC_MANAGER_PK_INVITATION_COLLECTION)
            .delete(id: invitation.objectId!,
                    success: { _ in
                agoraPrint("imp pk invitation remove success... \(channelName)")
                completion(nil)
            }, fail: { error in
                agoraPrint("imp pk invitation remove fail :\(error.message)... \(channelName)")
                completion(error.toNSError())
            })
    }
    
    private func _updatePKInvitation(invitation: ShowPKInvitation, completion: @escaping (NSError?) -> Void) {
        let channelName = invitation.roomId
        if channelName.isEmpty {return}
        agoraPrint("imp pk invitation update... \(channelName)")

        let params = invitation.yy_modelToJSONObject() as! [String: Any]
        SyncUtil
            .scene(id: channelName)?
            .collection(className: SYNC_MANAGER_PK_INVITATION_COLLECTION)
            .update(id: invitation.objectId!,
                    data:params,
                    success: {
                agoraPrint("imp pk invitation update success... \(channelName)")
                completion(nil)
            }, fail: { error in
                agoraPrint("imp pk invitation update fail :\(error.message)... \(channelName)")
                completion(error.toNSError())
            })
    }
    
    private func _recvPKRejected(invitation: ShowPKInvitation) {
        guard roomId == invitation.fromRoomId else { return }
        let pkRoomId = invitation.roomId
        if pkRoomId == roomId {
            return
        }
        _unsubscribePKInvitationChanged(roomId: pkRoomId)
//        SyncUtil.scene(id: pkRoomId)?.deleteScenes()
        _leaveScene(roomId: pkRoomId)
//        guard let interaction = self.interactionList.filter({ $0.userId == invitation.userId }).first else { return }
//        _removeInteraction(interaction: interaction) { error in
//        }
        self.pkCreatedInvitationMap[pkRoomId] = nil
        
        self.subscribeDelegate?.onPKInvitationRejected(invitation: invitation)
    }
    
    private func _recvPKAccepted(invitation: ShowPKInvitation) {
        guard roomId == invitation.fromRoomId else { return }
        if let _ = self.interactionList.filter({ $0.userId == invitation.userId }).first {
            return
        }
        
        //reject if already has interation
        if self.interactionList.count > 0 {
            _removePKInvitation(invitation: invitation) { err in
            }
            return
        }
        
        //reset mute status if start interaction
        self.userMuteLocalAudio = false
        
        let interaction = ShowInteractionInfo()
        interaction.userId = invitation.userId
        interaction.userName = invitation.userName
        interaction.roomId = invitation.roomId
        interaction.interactStatus = .pking
//        interaction.muteAudio = invitation.userMuteAudio
//        interaction.ownerMuteAudio = self.userMuteLocalAudio
        interaction.createdAt = Int64(Date().timeIntervalSince1970 * 1000)
        _addInteraction(interaction: interaction) { error in
        }
        
        self.subscribeDelegate?.onPKInvitationAccepted(invitation: invitation)
        
        //cancel others pk invitation
        self.pkCreatedInvitationMap.forEach { (key: String, value: ShowPKInvitation) in
            if key == invitation.roomId { return }
            self._removePKInvitation(invitation: value) { err in
            }
        }
        
    }
    
    private func _recvPKFinish(invitation: ShowPKInvitation) {
        guard roomId == invitation.fromRoomId else { return }
        let pkRoomId = invitation.roomId
        _unsubscribePKInvitationChanged(roomId: pkRoomId)
//        SyncUtil.scene(id: pkRoomId)?.deleteScenes()
        _leaveScene(roomId: pkRoomId)
        guard let interaction = self.interactionList.filter({ $0.userId == invitation.userId }).first else {
            return
        }
        
        _removeInteraction(interaction: interaction) { error in
        }
        self.pkCreatedInvitationMap[invitation.roomId] = nil
    }
    
    func _getCurrentApplyUser(roomId: String?, completion: @escaping (ShowRoomListModel?) -> Void) {
        guard let channelName = roomId else {
            agoraPrint("_updatePKInvitation channelName = nil")
            return
        }
        agoraPrint("imp pk invitation update...")
        _getRoomList(page: 0) { _, roomList in
            let model = roomList?.filter({ $0.roomId == channelName && $0.interactStatus != .idle }).first
            completion(model)
        }
    }
    
    //recv pk invitation feedback(accpet/reject/...)
    func _handleCreatePkInvitationRespone(invitation: ShowPKInvitation, status: ShowSubscribeStatus) {
        if status == .created {
            self.pkCreatedInvitationMap[invitation.roomId] = invitation
        }
        guard let model = self.pkCreatedInvitationMap.values.filter({ $0.objectId == invitation.objectId }).first else {
            return
        }
        model.userMuteAudio = invitation.userMuteAudio
        model.fromUserMuteAudio = invitation.fromUserMuteAudio
        if status == .deleted {
            if model.status == .accepted {
                self._recvPKFinish(invitation: model)
            } else {
                self._recvPKRejected(invitation: model)
            }
        } else {
            model.status = invitation.status
            switch model.status {
            case .rejected:
                self._recvPKRejected(invitation: model)
            case .accepted:
                self._recvPKAccepted(invitation: model)
            case .ended:
                self._recvPKFinish(invitation: model)
                self.subscribeDelegate?.onPKInvitationUpdated(invitation: model)
            default:
                self.subscribeDelegate?.onPKInvitationUpdated(invitation: model)
                break
            }
            
            //TODO: workaround
            guard let interaction = self.interactionList.filter({ $0.userId == model.userId}).first else {return}
            if interaction.ownerMuteAudio == model.fromUserMuteAudio,
                interaction.muteAudio == model.userMuteAudio {
                return
            }
            interaction.muteAudio = model.userMuteAudio
            interaction.ownerMuteAudio = model.fromUserMuteAudio
            self._updateInteraction(interaction: interaction) { err in
            }
        }
    }
}

//MARK: Interaction
extension ShowSyncManagerServiceImp {
    private func _getAllInteractionList(completion: @escaping (NSError?, [ShowInteractionInfo]?) -> Void) {
        guard let channelName = roomId else {
            agoraPrint("channelName = nil")
            return
        }
        agoraPrint("imp interaction get... \(channelName)")
        SyncUtil
            .scene(id: channelName)?
            .collection(className: SYNC_MANAGER_INTERACTION_COLLECTION)
            .get(success: { [weak self] list in
                agoraPrint("imp interaction get success... \(list.count) \(channelName)")
                let interactionList = list.compactMap({ ShowInteractionInfo.yy_model(withJSON: $0.toJson()!)! })
                self?.interactionList = interactionList
                completion(nil, interactionList)
            }, fail: { error in
                agoraPrint("imp interaction get fail :\(error.message)... \(channelName)")
                completion(error.toNSError(), nil)
            })
    }
    
    private func _subscribeInteractionChanged() {
        guard let channelName = roomId else {
            agoraAssert("channelName = nil")
            return
        }
        agoraPrint("imp interaction subscribe ... \(channelName)")
        SyncUtil
            .scene(id: channelName)?
            .subscribe(key: SYNC_MANAGER_INTERACTION_COLLECTION,
                       onCreated: { [weak self] object in
                guard let self = self,
                      let jsonStr = object.toJson(),
                      let model = ShowInteractionInfo.yy_model(withJSON: jsonStr) else {
                    return
                }
                if let index = self.interactionList.firstIndex(where: { $0.userId == model.userId }) {
                    self.interactionList.remove(at: index)
                    self.interactionList.insert(model, at: index)
                    //callback before send msg success
//                    self.subscribeDelegate?.onInteractionBegan(interaction: model)
                    return
                }
            }, onUpdated: { [weak self] object in
                agoraPrint("imp interaction subscribe onUpdated... \(channelName)")
                guard let self = self,
                      let jsonStr = object.toJson(),
                      let model = ShowInteractionInfo.yy_model(withJSON: jsonStr) else {
                    return
                }
                let userId = model.userId
                let index = self.interactionList.firstIndex(where: { $0.userId == model.userId })
                if let index = index, !self.interactionPaddingIdsSet.contains(userId) {
                    self.interactionList.remove(at: index)
                    self.interactionList.insert(model, at: index)
                    self.subscribeDelegate?.onInterationUpdated(interaction: model)
                    return
                }
                self.interactionPaddingIdsSet.remove(userId)
                if let index = index {
                    self.interactionList.remove(at: index)
                }
                self.interactionList.append(model)
                self.subscribeDelegate?.onInteractionBegan(interaction: model)
            }, onDeleted: {[weak self] object in
                agoraPrint("imp interaction subscribe onDeleted... \(channelName)")
                guard let self = self else {return}
                var model: ShowInteractionInfo? = nil
                if let index = self.interactionList.firstIndex(where: { object.getId() == $0.objectId }) {
                    model = self.interactionList[index]
                    self.interactionList.remove(at: index)
                }
                guard let _invitation = model ?? ShowInteractionInfo.yy_model(withJSON: object.toJson() ?? "") else {
                    agoraAssert("fail to handle delete pk invitation \(channelName)")
                    return
                }
                self.subscribeDelegate?.onInterationEnded(interaction: _invitation)
                self.cancelMicSeatApply { _ in }
            }, onSubscribed: {
            }, fail: { error in
                agoraPrint("imp interaction subscribe fail \(error.message)... \(channelName)")
                ToastView.show(text: error.message)
            })
                           
    }
    
    private func _addInteraction(interaction: ShowInteractionInfo, completion: @escaping (NSError?) -> Void) {
        guard let channelName = roomId else {
//            assert(false, "channelName = nil")
            agoraPrint("_addInteraction channelName = nil")
            return
        }
        agoraPrint("imp interaction add ... \(channelName)")

        let params = interaction.yy_modelToJSONObject() as! [String: Any]
        //add interation immediately to prevent received multi pk invitations at the same time
        interactionList.append(interaction)
        interactionPaddingIdsSet.insert(interaction.userId ?? "")
        SyncUtil
            .scene(id: channelName)?
            .collection(className: SYNC_MANAGER_INTERACTION_COLLECTION)
            .add(data: params, success: { object in
                agoraPrint("imp interaction add success... \(channelName)")
                completion(nil)
            }, fail: { error in
                agoraPrint("imp interaction add fail :\(error.message)... \(channelName)")
                completion(error.toNSError())
            })
        
        _updateInteractionStatus(with: interaction.interactStatus)
        
        
    }
    
    private func _removeInteraction(invitation: ShowPKInvitation, completion: @escaping (NSError?) -> Void) {
        //TODO:
        let userIds = [invitation.fromUserId, invitation.userId]
        guard let interaction = self.interactionList.filter({ userIds.contains($0.userId) }).first else {
            return
        }
        
        _removeInteraction(interaction: interaction, completion: completion)
    }
    
    private func _removeInteraction(interaction: ShowInteractionInfo, completion: @escaping (NSError?) -> Void) {
        guard let channelName = roomId else {
            agoraPrint("_removeInteraction channelName = nil")
            return
        }
        agoraPrint("imp interaction remove... \(channelName)")

        SyncUtil
            .scene(id: channelName)?
            .collection(className: SYNC_MANAGER_INTERACTION_COLLECTION)
            .delete(id: interaction.objectId!,
                    success: { _ in
                agoraPrint("imp interaction remove success... \(channelName)")
                completion(nil)
            }, fail: { error in
                agoraPrint("imp interaction remove fail :\(error.message)... \(channelName)")
                completion(error.toNSError())
            })
        _updateInteractionStatus(with: .idle)
    }
    
    private func _updateInteraction(interaction: ShowInteractionInfo, completion: @escaping (NSError?) -> Void) {
        guard let channelName = roomId else {
            agoraPrint("_updateInteraction channelName = nil")
            return
        }
        agoraPrint("imp interaction update... \(channelName)")

        let params = interaction.yy_modelToJSONObject() as! [String: Any]
        SyncUtil
            .scene(id: channelName)?
            .collection(className: SYNC_MANAGER_INTERACTION_COLLECTION)
            .update(id: interaction.objectId!,
                    data:params,
                    success: {
                agoraPrint("imp interaction update success... \(channelName)")
                completion(nil)
            }, fail: { error in
                agoraPrint("imp interaction update fail :\(error.message)... \(channelName)")
                completion(error.toNSError())
            })
    }
}

//lost connected
extension ShowSyncManagerServiceImp {
    private func _fetchCreatePkInvitation() {
        _getRoomList(page: 0) { [weak self] (err, list) in
            guard let self = self else { return }
            self.pkCreatedInvitationMap.forEach { (key: String, value: ShowPKInvitation) in
                guard let room = list?.filter({ $0.roomId == key }).first else {
                    //room did remove
                    self._handleCreatePkInvitationRespone(invitation: value, status: .deleted)
                    return
                }
                self._getAllPKInvitationList(room: room) { err, list in
                    guard let invitation = list?.filter({ $0.objectId == value.objectId }).first else {
                        // invitation did remove
                        self._handleCreatePkInvitationRespone(invitation: value, status: .deleted)
                        return
                    }
                    
                    guard invitation == value else {
                        return
                    }
                    
                    self._handleCreatePkInvitationRespone(invitation: invitation, status: .updated)
                }
            }
        }
    }
}


private let robotRoomIds = ["1", "2", "3"]
private let robotRoomOwnerHeaders = [
    "https://download.agora.io/demo/release/bot1.png"
]
private let robotStreamURL = [
    "https://download.agora.io/sdk/release/agora_test_video_10.mp4",
    "https://download.agora.io/sdk/release/agora_test_video_11.mp4",
    "https://download.agora.io/sdk/release/agora_test_video_12.mp4",
]

private let kRobotRoomStartId = 2023000
private let kRobotUid = 2000000001
class ShowRobotSyncManagerServiceImp: ShowSyncManagerServiceImp {
    deinit {
        agoraPrint("deinit-- ShowRobotSyncManagerServiceImp")
    }
    
    override func isOwner(_ room: ShowRoomListModel) -> Bool {
        if room.roomId.count == 6 {
            return super.isOwner(room)
        }
        
        return true
    }
    
    override func _checkRoomExpire() {
        guard let room = self.room else { return }
        let roomId = room.roomId
        if room.roomId.count == 6 {
            return super._checkRoomExpire()
        }
        
        NetworkManager.shared.cloudPlayerHeartbeat(channelName: roomId, uid: room.ownerId) { msg in
            guard let msg = msg else {return}
            agoraAssert("cloudPlayerHeartbeat fail: \(roomId) \(msg)")
        }
        
    }
    
    @objc override func _getRoomList(page: Int, completion: @escaping (NSError?, [ShowRoomListModel]?) -> Void) {
        initScene { error in
            if let error = error {
                completion(error, nil)
                return
            }
            SyncUtil.fetchAll { results in
                agoraPrint("result == \(results.compactMap { $0.toJson() })")
                var dataArray = results.map({ info in
                    return ShowRoomListModel.yy_model(with: info.toJson()!.toDictionary())!
                })
                
                var robotIds = robotRoomIds
                dataArray.forEach { room in
                    let roomId = (Int(room.roomId) ?? 0) - kRobotRoomStartId
                    guard roomId > 0, let idx = robotIds.firstIndex(of: "\(roomId)") else{
                        return
                    }
                    robotIds.remove(at: idx)
                }
                
                //create fake room
                robotIds.forEach { robotId in
                    let room = ShowRoomListModel()
                    let robotId = Int(robotId) ?? 1
                    let userId = "\(kRobotUid)"
                    room.roomName = "Smooth \(robotId)"
                    room.roomId = "\(robotId + kRobotRoomStartId)"
                    room.thumbnailId = "1"
                    room.ownerId = userId
                    room.ownerName = userId
                    room.ownerAvatar = robotRoomOwnerHeaders[(robotId - 1) % robotRoomOwnerHeaders.count]//VLUserCenter.user.headUrl
                    room.createdAt = Date().millionsecondSince1970()
                    dataArray.append(room)
                }
                
//                let roomList = dataArray.sorted(by: { ($0.updatedAt > 0 ? $0.updatedAt : $0.createdAt) > ($1.updatedAt > 0 ? $1.updatedAt : $1.createdAt) })
                let roomList = dataArray.sorted(by: { $0.createdAt > $1.createdAt })
                completion(nil, roomList)
            } fail: { error in
                completion(error.toNSError(), nil)
            }
        }
    }
    
    @objc override func createRoom(roomName: String,
                                   roomId: String,
                                   thumbnailId: String,
                                   completion: @escaping (NSError?, ShowRoomDetailModel?) -> Void) {
        super.createRoom(roomName: roomName, roomId: roomId, thumbnailId: thumbnailId, completion: completion)
        
        startCloudPlayer(roomId: roomId, robotUid: UInt(kRobotUid))
    }
    
    @objc override func joinRoom(room: ShowRoomListModel,
                        completion: @escaping (NSError?, ShowRoomDetailModel?) -> Void) {
        super.joinRoom(room: room, completion: completion)
        
        startCloudPlayer(roomId: room.roomId, robotUid: UInt(room.ownerId) ?? 0)
    }
    
    override func createMicSeatApply(completion: @escaping (NSError?) -> Void) {
        completion(ShowError.userCannotAccept.toNSError())
    }
    
    
    //MARK: private
    private func startCloudPlayer(roomId: String?, robotUid: UInt) {
        guard let roomId = roomId, roomId.count == 7 else {
            return
        }
        let channelName = roomId
        let idx = ((Int(channelName) ?? 1) - kRobotRoomStartId - 1) % robotStreamURL.count
        agoraPrint("startCloudPlayer: \(roomId) /\(robotUid)")
        NetworkManager.shared.startCloudPlayer(channelName: channelName,
                                               uid: VLUserCenter.user.id,
                                               robotUid: UInt(kRobotUid),
                                               streamUrl: robotStreamURL[idx]) { msg in
            guard let msg = msg else {return}
            agoraPrint("startCloudPlayer fail \(channelName) \(msg)")
        }
    }
    
}
