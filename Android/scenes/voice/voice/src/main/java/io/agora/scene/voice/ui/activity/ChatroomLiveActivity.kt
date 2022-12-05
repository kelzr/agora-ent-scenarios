package io.agora.scene.voice.ui.activity

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.text.TextUtils
import android.util.Log
import android.view.KeyEvent
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.Toast
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.isVisible
import androidx.lifecycle.ViewModelProvider
import io.agora.CallBack
import io.agora.scene.voice.imkit.bean.ChatMessageData
import io.agora.scene.voice.imkit.custorm.CustomMsgHelper
import io.agora.voice.common.ui.BaseUiActivity
import io.agora.voice.common.ui.adapter.listener.OnItemClickListener
import io.agora.voice.common.net.OnResourceParseCallback
import io.agora.voice.common.utils.StatusBarCompat
import io.agora.voice.common.utils.ThreadManager
import io.agora.voice.common.utils.ToastTools
import io.agora.chat.ChatClient
import io.agora.scene.voice.R
import io.agora.voice.common.utils.LogTools.logE
import io.agora.scene.voice.databinding.VoiceActivityChatroomBinding
import io.agora.scene.voice.model.constructor.RoomInfoConstructor.convertByVoiceRoomModel
import io.agora.scene.voice.imkit.manager.ChatroomIMManager
import io.agora.scene.voice.viewmodel.VoiceRoomLivingViewModel
import io.agora.scene.voice.global.VoiceBuddyFactory
import io.agora.scene.voice.imkit.custorm.OnMsgCallBack
import io.agora.scene.voice.model.*
import io.agora.scene.voice.service.VoiceRoomServiceKickedReason
import io.agora.scene.voice.service.VoiceRoomSubscribeDelegate
import io.agora.scene.voice.service.VoiceServiceProtocol
import io.agora.voice.common.net.Resource
import io.agora.scene.voice.ui.RoomGiftViewDelegate
import io.agora.scene.voice.ui.RoomObservableViewDelegate
import io.agora.scene.voice.ui.widget.barrage.RoomMessagesView
import io.agora.scene.voice.ui.widget.primary.MenuItemClickListener
import io.agora.scene.voice.ui.widget.top.OnLiveTopClickListener
import io.agora.voice.common.constant.ConfigConstants
import io.agora.voice.common.utils.LogTools.logD
import pub.devrel.easypermissions.EasyPermissions
import pub.devrel.easypermissions.PermissionRequest

class ChatroomLiveActivity : BaseUiActivity<VoiceActivityChatroomBinding>(), EasyPermissions.PermissionCallbacks,
    EasyPermissions.RationaleCallbacks, VoiceRoomSubscribeDelegate {

    companion object {
        const val RC_PERMISSIONS = 101
        const val KEY_VOICE_ROOM_MODEL = "voice_chat_room_model"

        fun startActivity(activity: Activity, voiceRoomModel: VoiceRoomModel) {
            val intent = Intent(activity, ChatroomLiveActivity::class.java).apply {
                putExtra(KEY_VOICE_ROOM_MODEL, voiceRoomModel)
            }
            activity.startActivity(intent)
        }
    }

    /**room viewModel*/
    private lateinit var roomLivingViewModel: VoiceRoomLivingViewModel
    private lateinit var giftViewDelegate: RoomGiftViewDelegate
    private val voiceServiceProtocol = VoiceServiceProtocol.getImplInstance()

    /**
     * 代理头部view以及麦位view
     */
    private lateinit var roomObservableDelegate: RoomObservableViewDelegate

    /** voice room info */
    private val voiceRoomModel: VoiceRoomModel by lazy {
        intent.getSerializableExtra(KEY_VOICE_ROOM_MODEL) as VoiceRoomModel
    }

    /**房间基础*/
    private val roomKitBean = RoomKitBean()

    override fun getViewBinding(inflater: LayoutInflater): VoiceActivityChatroomBinding {
        window.setFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON, WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        return VoiceActivityChatroomBinding.inflate(inflater)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        StatusBarCompat.setLightStatusBar(this, false)
        roomLivingViewModel = ViewModelProvider(this)[VoiceRoomLivingViewModel::class.java]
        giftViewDelegate =
            RoomGiftViewDelegate.getInstance(this, roomLivingViewModel, binding.chatroomGiftView, binding.svgaView)
        initListeners()
        initData()
        initView()
        requestAudioPermission()
    }

    private fun initData() {
        roomKitBean.convertByVoiceRoomModel(voiceRoomModel)
        giftViewDelegate.onRoomDetails(roomKitBean.roomId, roomKitBean.ownerId)
        ChatroomIMManager.getInstance().init(roomKitBean.chatroomId)
        ChatroomIMManager.getInstance().saveWelcomeMsg(
            getString(R.string.voice_room_welcome),
            VoiceBuddyFactory.get().getVoiceBuddy().nickName()
        )
        binding.messageView.refreshSelectLast()
//        roomLivingViewModel.fetchRoomDetail(voiceRoomModel)
    }

    private fun initListeners() {
        // 房间详情
        roomLivingViewModel.roomDetailsObservable().observe(this) { response: Resource<VoiceRoomInfo> ->
            parseResource(response, object : OnResourceParseCallback<VoiceRoomInfo>() {

                override fun onLoading(data: VoiceRoomInfo?) {
                    super.onLoading(data)
                    showLoading(false)
                }

                override fun onHideLoading() {
                    super.onHideLoading()
                    dismissLoading()
                }

                override fun onSuccess(data: VoiceRoomInfo?) {
                    data?.let {
                        roomObservableDelegate.onRoomDetails(it)
                        ChatroomIMManager.getInstance().setMemberList(ChatroomIMManager.getInstance().mySelfModel)
                    }
                }
            })
        }
        roomLivingViewModel.joinObservable().observe(this) { response: Resource<Boolean> ->
            parseResource(response, object : OnResourceParseCallback<Boolean>() {

                override fun onSuccess(data: Boolean?) {
                    ToastTools.show(this@ChatroomLiveActivity, getString(R.string.voice_chatroom_join_room_success))
                    roomLivingViewModel.fetchRoomDetail(voiceRoomModel)
                    CustomMsgHelper.getInstance().sendSystemMsg(
                        roomKitBean.ownerChatUid, object : OnMsgCallBack() {
                            override fun onSuccess(message: ChatMessageData?) {
                                "sendSystemMsg onSuccess $message".logE()
                                binding.messageView.refreshSelectLast()
                            }

                            override fun onError(messageId: String?, code: Int, error: String?) {
                                "sendSystemMsg onFail $code $error".logE()
                            }
                        }
                    )
                }

                override fun onError(code: Int, message: String?) {
                    ToastTools.show(
                        this@ChatroomLiveActivity,
                        message ?: getString(R.string.voice_chatroom_join_room_failed)
                    )
                    ThreadManager.getInstance().runOnMainThreadDelay({
                        finish()
                    }, 1000)
                }
            })
        }
        ViewCompat.setOnApplyWindowInsetsListener(binding.root) { _: View?, insets: WindowInsetsCompat ->
            val systemInset = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            "systemInset:left:${systemInset.left},top:${systemInset.top},right:${systemInset.right},bottom:${systemInset.bottom}".logE(
                "insets=="
            )
            binding.clMain.setPaddingRelative(0, systemInset.top, 0, systemInset.bottom)
            WindowInsetsCompat.CONSUMED
        }
        binding.clMain.setOnTouchListener { v, event ->
            reset()
            false
        }
        binding.messageView.setMessageViewListener(object : RoomMessagesView.MessageViewListener {
            override fun onItemClickListener(message: ChatMessageData?) {
            }

            override fun onListClickListener() {
                reset()
            }
        })
        voiceServiceProtocol.subscribeEvent(object : VoiceRoomSubscribeDelegate{
            override fun onReceiveGift(roomId: String, message: ChatMessageData?) {
                super.onReceiveGift(roomId, message)
                if (!TextUtils.equals(roomKitBean.chatroomId, roomId)) return
                binding.chatroomGiftView.refresh()
                if (CustomMsgHelper.getInstance().getMsgGiftId(message).equals("VoiceRoomGift9")) {
                    giftViewDelegate.showGiftAction()
                }
                roomObservableDelegate.receiveGift(roomKitBean.roomId,message)
            }

            override fun onReceiveTextMsg(roomId: String, message: ChatMessageData?) {
                super.onReceiveTextMsg(roomId, message)
                if (!TextUtils.equals(roomKitBean.chatroomId, roomId)) return
                binding.messageView.refreshSelectLast()
            }

            override fun onReceiveSeatRequest(roomId: String, applicant: ChatMessageData) {
                super.onReceiveSeatRequest(roomId, applicant)
                "onReceiveSeatRequest ${roomKitBean.isOwner}".logE("liveActivity")
                binding.chatBottom.setShowHandStatus(roomKitBean.isOwner, true)
            }

            override fun onReceiveSeatRequestRejected(roomId: String, chatUid: String) {
                super.onReceiveSeatRequestRejected(roomId, chatUid)
                "onReceiveSeatRequestRejected $chatUid".logE("liveActivity")
                ThreadManager.getInstance().runOnMainThread {
                    //刷新 owner 申请列表
                    roomObservableDelegate.handsUpdate(0)
                }
                ChatroomIMManager.getInstance().removeSubmitMember(chatUid)
            }

            override fun onReceiveSeatInvitation(roomId: String, message: ChatMessageData) {
                super.onReceiveSeatInvitation(roomId, message)
                "onReceiveSeatInvitation $message".logE("liveActivity")
                roomObservableDelegate.receiveInviteSite(roomKitBean.roomId, -1)
            }

            override fun onReceiveSeatInvitationRejected(
                roomId: String,
                message: ChatMessageData?
            ) {
                super.onReceiveSeatInvitationRejected(roomId, message)
                "onReceiveSeatInvitationRejected $message".logE("liveActivity")
            }

            override fun onAnnouncementChanged(roomId: String, content: String) {
                super.onAnnouncementChanged(roomId, content)
                "onAnnouncementChanged $content".logE("liveActivity")
                if (!TextUtils.equals(roomKitBean.chatroomId, roomId)) return
                roomObservableDelegate.updateAnnouncement(content)
            }

            override fun onUserJoinedRoom(roomId: String, voiceMember: VoiceMemberModel) {
                super.onUserJoinedRoom(roomId, voiceMember)
                if (!TextUtils.equals(roomKitBean.chatroomId, roomId)) return
                voiceRoomModel.memberCount = voiceRoomModel.memberCount + 1
                voiceRoomModel.clickCount = voiceRoomModel.clickCount + 1
                ThreadManager.getInstance().runOnMainThread {
                    binding.cTopView.onUpdateMemberCount(voiceRoomModel.memberCount)
                    binding.cTopView.onUpdateWatchCount(voiceRoomModel.clickCount)
                }
                voiceMember.let {
                    ChatroomIMManager.getInstance().setMemberList(it)
                }
                binding.messageView.refreshSelectLast()
            }

            override fun onUserLeftRoom(roomId: String, chatUid: String) {
                super.onUserLeftRoom(roomId, chatUid)
                if (!TextUtils.equals(roomKitBean.chatroomId, roomId)) return
                chatUid.let { ChatroomIMManager.getInstance().removeMember(it) }
                voiceRoomModel.memberCount = voiceRoomModel.memberCount - 1
                ThreadManager.getInstance().runOnMainThread {
                    binding.cTopView.onUpdateMemberCount(voiceRoomModel.memberCount)
                }
            }

            override fun onUserBeKicked(roomId: String, reason: VoiceRoomServiceKickedReason) {
                super.onUserBeKicked(roomId, reason)
                if (!TextUtils.equals(roomKitBean.chatroomId, roomId)) return
                Log.e("ChatroomLiveActivity", "userBeKicked: $reason")
                if (reason == VoiceRoomServiceKickedReason.destroyed) {
                    ToastTools.show(this@ChatroomLiveActivity, getString(R.string.voice_room_close), Toast.LENGTH_SHORT)
                    finish()
                } else if (reason == VoiceRoomServiceKickedReason.removed) {
                    ToastTools.show(this@ChatroomLiveActivity, getString(R.string.voice_room_kick_member), Toast.LENGTH_SHORT)
                    finish()
                }
            }

            override fun onSeatUpdated(
                roomId: String,
                attributeMap: Map<String, String>,
                fromId: String
            ) {
                super.onSeatUpdated(roomId, attributeMap, fromId)
                "roomAttributesDidUpdated ${Thread.currentThread()},roomId:$roomId,fromId:$fromId,map:$attributeMap".logE()
                if (isFinishing || !TextUtils.equals(roomKitBean.chatroomId, roomId)) return
                attributeMap.let {
                    ChatroomIMManager.getInstance().updateMicInfoCache(it)
                    roomObservableDelegate.onSeatUpdated(it)
                }
            }

            override fun onRoomDestroyed(roomId: String) {
                super.onRoomDestroyed(roomId)
                if (!TextUtils.equals(roomKitBean.chatroomId, roomId)) return
                Log.e("ChatroomLiveActivity", "onRoomDestroyed: ")
                ToastTools.show(this@ChatroomLiveActivity, getString(R.string.voice_room_close), Toast.LENGTH_SHORT)
                finish()
            }
        })
    }

    private fun initView() {
        binding.chatBottom.initMenu(roomKitBean.roomType)
        if (roomKitBean.roomType == ConfigConstants.RoomType.Common_Chatroom) { // 普通房间
            binding.likeView.likeView.setOnClickListener { binding.likeView.addFavor() }
            binding.chatroomGiftView.init(roomKitBean.chatroomId)
            binding.messageView.init(roomKitBean.chatroomId, roomKitBean.ownerChatUid)
            binding.rvChatroom2dMicLayout.isVisible = true
            binding.rvChatroom3dMicLayout.isVisible = false
            roomObservableDelegate =
                RoomObservableViewDelegate(
                    this,
                    roomLivingViewModel,
                    roomKitBean,
                    binding.cTopView,
                    binding.rvChatroom2dMicLayout,
                    binding.chatBottom
                )
            binding.rvChatroom2dMicLayout.setMyRtcUid(VoiceBuddyFactory.get().getVoiceBuddy().rtcUid())
            binding.rvChatroom2dMicLayout.onItemClickListener(
                object :
                    OnItemClickListener<VoiceMicInfoModel> {
                    override fun onItemClick(data: VoiceMicInfoModel, view: View, position: Int, viewType: Long) {
                        roomObservableDelegate.onUserMicClick(data)
                    }
                },
                object :
                    OnItemClickListener<VoiceMicInfoModel> {
                    override fun onItemClick(data: VoiceMicInfoModel, view: View, position: Int, viewType: Long) {
                        roomObservableDelegate.onBotMicClick(getString(R.string.voice_chatroom_open_bot_prompt))
                    }
                }
            ).setUpInitAdapter()
        } else { // 空间音效房间
            binding.likeView.isVisible = false
            binding.rvChatroom2dMicLayout.isVisible = false
            binding.rvChatroom3dMicLayout.isVisible = true
            roomObservableDelegate =
                RoomObservableViewDelegate(
                    this,
                    roomLivingViewModel,
                    roomKitBean,
                    binding.cTopView,
                    binding.rvChatroom3dMicLayout,
                    binding.chatBottom
                )
            binding.rvChatroom3dMicLayout.setMyRtcUid(VoiceBuddyFactory.get().getVoiceBuddy().rtcUid())
            binding.rvChatroom3dMicLayout.onItemClickListener(
                object :
                    OnItemClickListener<VoiceMicInfoModel> {
                    override fun onItemClick(data: VoiceMicInfoModel, view: View, position: Int, viewType: Long) {
                        roomObservableDelegate.onUserMicClick(data)
                    }
                },
                object :
                    OnItemClickListener<VoiceMicInfoModel> {
                    override fun onItemClick(data: VoiceMicInfoModel, view: View, position: Int, viewType: Long) {
                        roomObservableDelegate.onBotMicClick(getString(R.string.voice_chatroom_open_bot_prompt))
                    }
                },
            ).setUpInitMicInfoMap()
        }
        binding.cTopView.setTitleMaxWidth()
        roomObservableDelegate.onRoomModel(voiceRoomModel)
        binding.cTopView.setOnLiveTopClickListener(object : OnLiveTopClickListener {
            override fun onClickBack(view: View) {

                if (roomKitBean.isOwner) {
                    roomObservableDelegate.onExitRoom(
                        getString(R.string.voice_chatroom_end_live),
                        getString(R.string.voice_chatroom_end_live_tips), finishBack = {
                            finish()
                        })
                } else {
                    roomObservableDelegate.checkUserLeaveMic()
                    finish()
                }
            }

            override fun onClickRank(view: View) {
                roomObservableDelegate.onClickRank()
            }

            override fun onClickNotice(view: View) {
                roomObservableDelegate.onClickNotice()
            }

            override fun onClickSoundSocial(view: View) {
                roomObservableDelegate.onClickSoundSocial(roomKitBean.soundEffect, finishBack = {
                    finish()
                })
            }
        })
        binding.chatBottom.setMenuItemOnClickListener(object : MenuItemClickListener {
            override fun onChatExtendMenuItemClick(itemId: Int, view: View?) {
                when (itemId) {
                    R.id.voice_extend_item_eq -> {
                        roomObservableDelegate.onAudioSettingsDialog(finishBack = {
                            finish()
                        })
                    }
                    R.id.voice_extend_item_mic -> {
                        roomObservableDelegate.onClickBottomMic()
                    }
                    R.id.voice_extend_item_hand_up -> {
                        roomObservableDelegate.onClickBottomHandUp()
                    }
                    R.id.voice_extend_item_gift -> {
                        giftViewDelegate.showGiftDialog(object : OnMsgCallBack() {
                            override fun onSuccess(message: ChatMessageData?) {
                                roomObservableDelegate.onSendGiftSuccess(roomKitBean.roomId,message)
                            }

                            override fun onError(messageId: String?, code: Int, error: String?) {
                                ToastTools.show(
                                    this@ChatroomLiveActivity,
                                    getString(R.string.voice_chatroom_send_gift_fail)
                                )
                            }
                        })
                    }
                }
            }

            override fun onInputLayoutClick() {
                checkFocus(false)
            }

            override fun onSendMessage(content: String?) {
                if (!content.isNullOrEmpty())
                    ChatroomIMManager.getInstance().sendTxtMsg(content,
                        VoiceBuddyFactory.get().getVoiceBuddy().nickName(),
                        object : OnMsgCallBack() {
                            override fun onSuccess(message: ChatMessageData?) {
                                ThreadManager.getInstance().runOnMainThread {
                                    binding.messageView.refreshSelectLast()
                                    binding.likeView.isVisible = true
                                }
                            }

                            override fun onError(code: Int, error: String?) {
                                Log.e("send error", " $code $error")
                            }
                        })
            }
        })
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_BACK && event.repeatCount == 0) {
            return false
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun finish() {
        binding.chatroomGiftView.clear()
        roomObservableDelegate.destroy()
        voiceServiceProtocol.unsubscribeEvent()
        ChatroomIMManager.getInstance().logout(false)
        ChatroomIMManager.getInstance().clearCache()
        if (roomKitBean.isOwner) {
            ChatClient.getInstance().chatroomManager().asyncDestroyChatRoom(roomKitBean.chatroomId, object :
                CallBack {
                override fun onSuccess() {}

                override fun onError(code: Int, error: String?) {}
            })
        }
        ChatClient.getInstance().chatroomManager().leaveChatRoom(roomKitBean.chatroomId)
        roomLivingViewModel.leaveSyncManagerRoom(roomKitBean.roomId)
        super.finish()
    }

    private fun requestAudioPermission() {
        val perms = arrayOf(Manifest.permission.RECORD_AUDIO)
        if (EasyPermissions.hasPermissions(this, *perms)) {
            onPermissionGrant()
        } else {
            // Do not have permissions, request them now
            EasyPermissions.requestPermissions(PermissionRequest.Builder(this, RC_PERMISSIONS, *perms).build())
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        // Forward results to EasyPermissions
        EasyPermissions.onRequestPermissionsResult(requestCode, permissions, grantResults, this)
    }

    private fun onPermissionGrant() {
        "onPermissionGrant initSdkJoin".logE()
        roomLivingViewModel.initSdkJoin(roomKitBean)
    }

    override fun onPermissionsGranted(requestCode: Int, perms: MutableList<String>) {
        "onPermissionsGranted requestCode$requestCode $perms".logD()
        if (requestCode == RC_PERMISSIONS) {
            onPermissionGrant()
        }
    }

    override fun onPermissionsDenied(requestCode: Int, perms: MutableList<String>) {
        "onPermissionsDenied $perms ".logD()
    }

    override fun onRationaleAccepted(requestCode: Int) {
        "onRationaleAccepted requestCode$requestCode ".logD()
        if (requestCode == RC_PERMISSIONS) {
            onPermissionGrant()
        }
    }

    override fun onRationaleDenied(requestCode: Int) {
        "onRationaleDenied requestCode$requestCode ".logD()
    }

    private fun reset() {
        if (roomKitBean.roomType == ConfigConstants.RoomType.Common_Chatroom) {
            binding.chatBottom.hideExpressionView(false)
            hideKeyboard()
            binding.chatBottom.showInput()
            binding.likeView.isVisible = true
            binding.chatBottom.hindViewChangeIcon()
        }
    }

    private fun checkFocus(focus: Boolean) {
        binding.likeView.isVisible = focus
    }
}