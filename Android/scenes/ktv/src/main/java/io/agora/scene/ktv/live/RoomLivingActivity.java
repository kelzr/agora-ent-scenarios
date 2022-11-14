package io.agora.scene.ktv.live;

import android.annotation.SuppressLint;
import android.app.ProgressDialog;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.Bundle;
import android.text.TextUtils;
import android.util.Log;
import android.view.KeyEvent;
import android.view.LayoutInflater;
import android.view.View;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.lifecycle.ViewModel;
import androidx.lifecycle.ViewModelProvider;

import java.util.Arrays;

import io.agora.rtc2.Constants;
import io.agora.scene.base.component.BaseRecyclerViewAdapter;
import io.agora.scene.base.component.BaseViewBindingActivity;
import io.agora.scene.base.component.OnButtonClickListener;
import io.agora.scene.base.component.OnItemClickListener;
import io.agora.scene.base.manager.UserManager;
import io.agora.scene.ktv.R;
import io.agora.scene.ktv.databinding.KtvActivityRoomLivingBinding;
import io.agora.scene.ktv.databinding.KtvItemRoomSpeakerBinding;
import io.agora.scene.ktv.live.fragment.dialog.MVFragment;
import io.agora.scene.ktv.live.holder.RoomPeopleHolder;
import io.agora.scene.ktv.live.listener.LrcActionListenerImpl;
import io.agora.scene.ktv.live.listener.SongActionListenerImpl;
import io.agora.scene.ktv.service.KTVJoinRoomOutputModel;
import io.agora.scene.ktv.service.VLRoomSeatModel;
import io.agora.scene.ktv.service.VLRoomSelSongModel;
import io.agora.scene.ktv.widget.LrcControlView;
import io.agora.scene.ktv.widget.MoreDialog;
import io.agora.scene.ktv.widget.MusicSettingDialog;
import io.agora.scene.ktv.widget.UserLeaveSeatMenuDialog;
import io.agora.scene.ktv.widget.song.SongDialog;
import io.agora.scene.widget.DividerDecoration;
import io.agora.scene.widget.dialog.CloseRoomDialog;
import io.agora.scene.widget.dialog.CommonDialog;
import io.agora.scene.widget.utils.UiUtils;

/**
 * 房间主页
 */
public class RoomLivingActivity extends BaseViewBindingActivity<KtvActivityRoomLivingBinding> {
    private static final String EXTRA_ROOM_INFO = "roomInfo";

    private RoomLivingViewModel roomLivingViewModel;
    private MoreDialog moreDialog;
    private MusicSettingDialog musicSettingDialog;
    private BaseRecyclerViewAdapter<KtvItemRoomSpeakerBinding, VLRoomSeatModel, RoomPeopleHolder> mRoomSpeakerAdapter;
    private CloseRoomDialog creatorExitDialog;

    private CommonDialog exitDialog;
    private UserLeaveSeatMenuDialog mUserLeaveSeatMenuDialog;
    private SongDialog mChooseSongDialog;
    private SongDialog mChorusSongDialog;

    private ProgressDialog mLoadingDialog;


    public static void launch(Context context, KTVJoinRoomOutputModel roomInfo) {
        Intent intent = new Intent(context, RoomLivingActivity.class);
        intent.putExtra(EXTRA_ROOM_INFO, roomInfo);
        context.startActivity(intent);
    }

    @Override
    protected KtvActivityRoomLivingBinding getViewBinding(@NonNull LayoutInflater inflater) {
        return KtvActivityRoomLivingBinding.inflate(inflater);
    }

    @Override
    public void initView(@Nullable Bundle savedInstanceState) {
        roomLivingViewModel = new ViewModelProvider(this, new ViewModelProvider.Factory() {
            @NonNull
            @Override
            public <T extends ViewModel> T create(@NonNull Class<T> aClass) {
                return (T) new RoomLivingViewModel((KTVJoinRoomOutputModel) getIntent().getSerializableExtra(EXTRA_ROOM_INFO));
            }
        }).get(RoomLivingViewModel.class);

        mRoomSpeakerAdapter = new BaseRecyclerViewAdapter<>(Arrays.asList(new VLRoomSeatModel[8]),
                new OnItemClickListener<VLRoomSeatModel>() {
                    @Override
                    public void onItemClick(@NonNull VLRoomSeatModel data, View view, int position, long viewType) {
                        OnItemClickListener.super.onItemClick(data, view, position, viewType);
                        if (!TextUtils.isEmpty(data.getUserNo())) {
                            if (roomLivingViewModel.isRoomOwner()) {
                                if (!mRoomSpeakerAdapter.dataList.get(position).getUserNo()
                                        .equals(UserManager.getInstance().getUser().userNo)) {
                                    showUserLeaveSeatMenuDialog(data);
                                }
                            } else if (mRoomSpeakerAdapter.dataList.get(position).getUserNo()
                                    .equals(UserManager.getInstance().getUser().userNo)) {
                                showUserLeaveSeatMenuDialog(data);
                            }
                        } else {
                            onItemClick(view, position, viewType);
                        }
                    }

                    @Override
                    public void onItemClick(View view, int position, long viewType) {
                        OnItemClickListener.super.onItemClick(view, position, viewType);
                        if (position == -1) return;
                        //点击坐位 上麦位
                        VLRoomSeatModel agoraMember = mRoomSpeakerAdapter.dataList.get(position);
                        if (agoraMember == null) {
                            VLRoomSeatModel seatLocal = roomLivingViewModel.seatLocalLiveData.getValue();
                            if (seatLocal == null || seatLocal.getSeatIndex() < 0) {
                                roomLivingViewModel.haveSeat(position);
                                requestRecordPermission();
                            }
                        }
                    }
                }, RoomPeopleHolder.class);
        getBinding().rvUserMember.addItemDecoration(new DividerDecoration(4, 24, 8));
        getBinding().rvUserMember.setAdapter(mRoomSpeakerAdapter);
        if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.R) {
            getBinding().rvUserMember.setOverScrollMode(View.OVER_SCROLL_NEVER);
        }
        getBinding().lrcControlView.setRole(LrcControlView.Role.Listener);
        getBinding().lrcControlView.post(() -> {
            roomLivingViewModel.init();

        });
        if (roomLivingViewModel.isRoomOwner()) {
            requestRecordPermission();
        }

        if (!TextUtils.isEmpty(roomLivingViewModel.roomInfoLiveData.getValue().getBgOption())) {
            setPlayerBgFromMsg(Integer.parseInt(roomLivingViewModel.roomInfoLiveData.getValue().getBgOption()));
        } else {
            setPlayerBgFromMsg(0);
        }
        getBinding().tvRoomName.setText(roomLivingViewModel.roomInfoLiveData.getValue().getRoomName());
    }

    @Override
    public void initListener() {
        getBinding().ivExit.setOnClickListener(view -> {
            showExitDialog();
        });
        getBinding().superLayout.setOnClickListener(view -> {
            setDarkStatusIcon(isBlackDarkStatus());
        });
        getBinding().cbMic.setOnCheckedChangeListener((compoundButton, b) -> {
            VLRoomSeatModel seatLocal = roomLivingViewModel.seatLocalLiveData.getValue();
            if (seatLocal == null || mRoomSpeakerAdapter.getItemData(seatLocal.getSeatIndex()) == null) {
                return;
            }
            roomLivingViewModel.toggleMic(b ? 0 : 1);
        });
        getBinding().iBtnChorus.setOnClickListener(v -> showChorusSongDialog());
        getBinding().iBtnChooseSong.setOnClickListener(v -> showChooseSongDialog());
        getBinding().btnMenu.setOnClickListener(this::showMoreDialog);
        getBinding().btnOK.setOnClickListener(view -> {
            getBinding().groupResult.setVisibility(View.GONE);
        });
        LrcActionListenerImpl lrcActionListenerImpl = new LrcActionListenerImpl(this, roomLivingViewModel, getBinding().lrcControlView) {
            @Override
            public void onMenuClick() {
                super.onMenuClick();
                showMusicSettingDialog();
            }

            @Override
            public void onChangeMusicClick() {
                super.onChangeMusicClick();
                showChangeMusicDialog();
            }
        };
        getBinding().lrcControlView.setOnLrcClickListener(lrcActionListenerImpl);
        getBinding().lrcControlView.setPitchViewOnActionListener(lrcActionListenerImpl);
        getBinding().cbVideo.setOnCheckedChangeListener((compoundButton, b) -> toggleSelfVideo(b));

        roomLivingViewModel.loadingDialogVisible.observe(this, this::showLoadingDialog);

        // 房间相关
        roomLivingViewModel.roomInfoLiveData.observe(this, ktvJoinRoomOutputModel -> {
            //修改背景
            if (!TextUtils.isEmpty(ktvJoinRoomOutputModel.getBgOption())) {
                setPlayerBgFromMsg(Integer.parseInt(ktvJoinRoomOutputModel.getBgOption()));
            }
        });
        roomLivingViewModel.roomDeleteLiveData.observe(this, deletedByCreator -> {
            if (deletedByCreator) {
                showCreatorExitDialog();
            } else {
                finish();
            }
        });
        roomLivingViewModel.roomUserCountLiveData.observe(this, count ->
                getBinding().tvRoomMCount.setText(getString(R.string.room_count, String.valueOf(count))));

        // 麦位相关
        roomLivingViewModel.seatLocalLiveData.observe(this, seatModel -> {
            boolean isOnSeat = seatModel != null && seatModel.getSeatIndex() >= 0;
            getBinding().groupBottomView.setVisibility(isOnSeat ? View.VISIBLE : View.GONE);
            getBinding().groupEmptyPrompt.setVisibility(isOnSeat ? View.GONE : View.VISIBLE);
        });
        roomLivingViewModel.seatListLiveData.observe(this, seatModels -> {
            if(seatModels == null){
                return;
            }
            for (VLRoomSeatModel seatModel : seatModels) {
                VLRoomSeatModel oSeatModel = mRoomSpeakerAdapter.dataList.get(seatModel.getSeatIndex());
                if (oSeatModel == null
                        || oSeatModel.isSelfMuted() != seatModel.isSelfMuted()
                        || oSeatModel.isVideoMuted() != seatModel.isVideoMuted()) {
                    mRoomSpeakerAdapter.dataList.set(seatModel.getSeatIndex(), seatModel);
                    mRoomSpeakerAdapter.notifyItemChanged(seatModel.getSeatIndex());
                }
            }
            for (VLRoomSeatModel seatModel : mRoomSpeakerAdapter.dataList) {
                if (seatModel == null) {
                    continue;
                }
                boolean exist = false;
                for (VLRoomSeatModel model : seatModels) {
                    if (seatModel.getSeatIndex() == model.getSeatIndex()) {
                        exist = true;
                        break;
                    }
                }
                if (!exist) {
                    onMemberLeave(seatModel);
                }
            }
        });


        // 歌词相关
        roomLivingViewModel.songsOrderedLiveData.observe(this, models -> {
            if (models == null || models.isEmpty()) {
                // songs empty
                getBinding().lrcControlView.setRole(LrcControlView.Role.Listener);
                getBinding().lrcControlView.onIdleStatus();
                mRoomSpeakerAdapter.notifyDataSetChanged();
            }
            if (mChooseSongDialog != null) {
                mChooseSongDialog.resetChosenSongList(SongActionListenerImpl.transSongModel(models));
            }
            if (mChorusSongDialog != null) {
                mChorusSongDialog.resetChosenSongList(SongActionListenerImpl.transSongModel(models));
            }
        });
        roomLivingViewModel.songPlayingLiveData.observe(this, model -> {
            if (model == null) return;
            onMusicChanged(model);
            getBinding().lrcControlView.setScoreControlView();
        });
        roomLivingViewModel.playerMusicStatusLiveData.observe(this, status -> {
            if (status == RoomLivingViewModel.PlayerMusicStatus.ON_PREPARE) {
                getBinding().lrcControlView.onPrepareStatus();
            } else if (status == RoomLivingViewModel.PlayerMusicStatus.ON_WAIT_CHORUS) {
                getBinding().lrcControlView.onWaitChorusStatus();
            } else if (status == RoomLivingViewModel.PlayerMusicStatus.ON_PLAYING) {
                getBinding().lrcControlView.onPlayStatus();
            } else if (status == RoomLivingViewModel.PlayerMusicStatus.ON_PAUSE) {
                getBinding().lrcControlView.onPauseStatus();
            } else if (status == RoomLivingViewModel.PlayerMusicStatus.ON_LRC_RESET) {
                getBinding().lrcControlView.getLrcView().reset();
            } else if (status == RoomLivingViewModel.PlayerMusicStatus.ON_CHANGING_START) {
                getBinding().lrcControlView.setEnabled(false);
            } else if (status == RoomLivingViewModel.PlayerMusicStatus.ON_CHANGING_END) {
                getBinding().lrcControlView.setEnabled(true);
            }
        });
        roomLivingViewModel.playerMusicLrcDataLiveData.observe(this, lrcData -> {
            getBinding().lrcControlView.getLrcView().setLrcData(lrcData);
            getBinding().lrcControlView.getPitchView().setLrcData(lrcData);
        });
        roomLivingViewModel.playerMusicOpenDurationLiveData.observe(this, duration -> {
            getBinding().lrcControlView.getLrcView().setTotalDuration(duration);
        });
        roomLivingViewModel.playerMusicPlayCompleteLiveData.observe(this, userNo -> {
            Log.d("cwtsw", "得分回调 userNo = " + UserManager.getInstance().getUser().userNo + " o = " + userNo);
            if (UserManager.getInstance().getUser().userNo.equals(userNo)) {
                Log.d("cwtsw", "计算得分");
                int score = (int) getBinding().lrcControlView.getPitchView().getAverageScore();
                getBinding().tvResultScore.setText(String.valueOf(score));
                if (score >= 90) {
                    getBinding().ivResultLevel.setImageResource(R.mipmap.ic_s);
                } else if (score >= 80) {
                    getBinding().ivResultLevel.setImageResource(R.mipmap.ic_a);
                } else if (score >= 60) {
                    getBinding().ivResultLevel.setImageResource(R.mipmap.ic_b);
                } else {
                    getBinding().ivResultLevel.setImageResource(R.mipmap.ic_c);
                }
                if (UserManager.getInstance().getUser().userNo.equals(roomLivingViewModel.songPlayingLiveData.getValue().getUserNo())) {
                    getBinding().groupResult.setVisibility(View.VISIBLE);
                    Log.d("cwtsw", "显示得分");
                }
            }
        });
        roomLivingViewModel.playerMusicPlayPositionChangeLiveData.observe(this, position -> {
            getBinding().lrcControlView.getLrcView().updateTime(position);
            getBinding().lrcControlView.getPitchView().updateTime(position);
        });
        roomLivingViewModel.playerMusicCountDownLiveData.observe(this, time ->
                getBinding().lrcControlView.setCountDown(time));
        roomLivingViewModel.playerPitchLiveData.observe(this, pitch ->
            getBinding().lrcControlView.getPitchView().updateLocalPitch(pitch.floatValue()));
        roomLivingViewModel.networkStatusLiveData.observe(this, netWorkStatus ->
                setNetWorkStatus(netWorkStatus.txQuality, netWorkStatus.rxQuality));
    }


    private void setNetWorkStatus(int txQuality, int rxQuality) {
        if (txQuality == Constants.QUALITY_BAD || txQuality == Constants.QUALITY_POOR
                || rxQuality == Constants.QUALITY_BAD || rxQuality == Constants.QUALITY_POOR) {
            getBinding().ivNetStatus.setImageResource(R.drawable.bg_round_yellow);
            getBinding().tvNetStatus.setText(R.string.net_status_m);
        } else if (txQuality == Constants.QUALITY_VBAD || txQuality == Constants.QUALITY_DOWN
                || rxQuality == Constants.QUALITY_VBAD || rxQuality == Constants.QUALITY_VBAD) {
            getBinding().ivNetStatus.setImageResource(R.drawable.bg_round_red);
            getBinding().tvNetStatus.setText(R.string.net_status_low);
        } else if (txQuality == Constants.QUALITY_EXCELLENT || txQuality == Constants.QUALITY_GOOD
                || rxQuality == Constants.QUALITY_EXCELLENT || rxQuality == Constants.QUALITY_GOOD) {
            getBinding().ivNetStatus.setImageResource(R.drawable.bg_round_green);
            getBinding().tvNetStatus.setText(R.string.net_status_good);
        } else if (txQuality == Constants.QUALITY_UNKNOWN || rxQuality == Constants.QUALITY_UNKNOWN) {
            getBinding().ivNetStatus.setImageResource(R.drawable.bg_round_red);
            getBinding().tvNetStatus.setText(R.string.net_status_un_know);
        } else {
            getBinding().ivNetStatus.setImageResource(R.drawable.bg_round_green);
            getBinding().tvNetStatus.setText(R.string.net_status_good);
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        Log.d("cwtsw", "onResume() " + isBlackDarkStatus());
        setDarkStatusIcon(isBlackDarkStatus());
    }

    /**
     * 下麦提示
     */
    private void showUserLeaveSeatMenuDialog(VLRoomSeatModel seatModel) {
        if (mUserLeaveSeatMenuDialog == null) {
            mUserLeaveSeatMenuDialog = new UserLeaveSeatMenuDialog(this);
        }
        mUserLeaveSeatMenuDialog.setOnButtonClickListener(new OnButtonClickListener() {
            @Override
            public void onLeftButtonClick() {
                setDarkStatusIcon(isBlackDarkStatus());
            }

            @Override
            public void onRightButtonClick() {
                setDarkStatusIcon(isBlackDarkStatus());
                roomLivingViewModel.leaveSeat(seatModel);
            }
        });
        mUserLeaveSeatMenuDialog.setAgoraMember(seatModel.getName(), seatModel.getHeadUrl());
        mUserLeaveSeatMenuDialog.show();
    }


    private void showExitDialog() {
        if (exitDialog == null) {
            exitDialog = new CommonDialog(this);

            if (roomLivingViewModel.isRoomOwner()) {
                exitDialog.setDialogTitle(getString(R.string.dismiss_room));
                exitDialog.setDescText(getString(R.string.confirm_to_dismiss_room));
            } else {
                exitDialog.setDialogTitle(getString(R.string.exit_room));
                exitDialog.setDescText(getString(R.string.confirm_to_exit_room));
            }
            exitDialog.setDialogBtnText(getString(R.string.ktv_cancel), getString(R.string.ktv_confirm));
            exitDialog.setOnButtonClickListener(new OnButtonClickListener() {
                @Override
                public void onLeftButtonClick() {
                    setDarkStatusIcon(isBlackDarkStatus());
                }

                @Override
                public void onRightButtonClick() {
                    setDarkStatusIcon(isBlackDarkStatus());
                    roomLivingViewModel.exitRoom();
                }
            });
        }
        exitDialog.show();
    }

    @SuppressLint("NotifyDataSetChanged")
    private void onMusicChanged(@NonNull VLRoomSelSongModel music) {
        getBinding().lrcControlView.setMusic(music);
        if (UserManager.getInstance().getUser().userNo.equals(music.getUserNo())
                || UserManager.getInstance().getUser().userNo.equals(music.getChorusNo())) {
//            RoomManager.mMine.role = AgoraMember.Role.Speaker;
            getBinding().lrcControlView.setRole(LrcControlView.Role.Singer);
        } else {
//            RoomManager.mMine.role = AgoraMember.Role.Listener;
            getBinding().lrcControlView.setRole(LrcControlView.Role.Listener);
        }
        roomLivingViewModel.musicStartPlay(this, music);
        mRoomSpeakerAdapter.notifyDataSetChanged();
    }


    public void closeMenuDialog() {
        setDarkStatusIcon(isBlackDarkStatus());
        moreDialog.dismiss();
    }

    private void showChorusSongDialog() {
        if (mChorusSongDialog == null) {
            mChorusSongDialog = new SongDialog();
            mChorusSongDialog.setChosenControllable(true);
            SongActionListenerImpl chooseSongListener =
                    new SongActionListenerImpl(this,
                            roomLivingViewModel, true);
            mChorusSongDialog.setChooseSongTabsTitle(
                    chooseSongListener.getSongTypeTitles(this),
                    0);
            mChorusSongDialog.setChooseSongListener(chooseSongListener);
        }
        roomLivingViewModel.getSongChosenList();
        mChorusSongDialog.show(getSupportFragmentManager(), "ChorusSongDialog");
    }

    private void showChooseSongDialog() {
        if (mChooseSongDialog == null) {
            mChooseSongDialog = new SongDialog();
            mChooseSongDialog.setChosenControllable(true);
            SongActionListenerImpl chooseSongListener =
                    new SongActionListenerImpl(this,
                            roomLivingViewModel, false);
            mChooseSongDialog.setChooseSongTabsTitle(
                    chooseSongListener.getSongTypeTitles(this),
                    0);
            mChooseSongDialog.setChooseSongListener(chooseSongListener);
        }
        roomLivingViewModel.getSongChosenList();
        mChooseSongDialog.show(getSupportFragmentManager(), "ChooseSongDialog");
    }

    private void showMoreDialog(View view) {
        if (moreDialog == null) {
            moreDialog = new MoreDialog(roomLivingViewModel.mSetting);
        }
        moreDialog.show(getSupportFragmentManager(), MoreDialog.TAG);
    }

    private void showMusicSettingDialog() {
        if (musicSettingDialog == null) {
            musicSettingDialog = new MusicSettingDialog(roomLivingViewModel.mSetting);
        }
        musicSettingDialog.show(getSupportFragmentManager(), MusicSettingDialog.TAG);
    }

    private CommonDialog changeMusicDialog;

    private void showChangeMusicDialog() {
        if (UiUtils.isFastClick(2000)) return;
        if (changeMusicDialog == null) {
            changeMusicDialog = new CommonDialog(this);
            changeMusicDialog.setDialogTitle(getString(R.string.ktv_room_change_music_title));
            changeMusicDialog.setDescText(getString(R.string.ktv_room_change_music_msg));
            changeMusicDialog.setDialogBtnText(getString(R.string.ktv_cancel), getString(R.string.ktv_confirm));
            changeMusicDialog.setOnButtonClickListener(new OnButtonClickListener() {
                @Override
                public void onLeftButtonClick() {
                    setDarkStatusIcon(isBlackDarkStatus());
                }

                @Override
                public void onRightButtonClick() {
                    setDarkStatusIcon(isBlackDarkStatus());
                    roomLivingViewModel.changeMusic();
                }
            });
        }
        changeMusicDialog.show();
    }

    public void setPlayerBgFromMsg(int position) {
        getBinding().lrcControlView.setLrcViewBackground(MVFragment.exampleBackgrounds.get(position));
    }

    public void setPlayerBg(int position) {
        roomLivingViewModel.setMV_BG(position);
        getBinding().lrcControlView.setLrcViewBackground(MVFragment.exampleBackgrounds.get(position));
    }

    @Override
    protected void onStart() {
        super.onStart();
        roomLivingViewModel.onStart();
    }

    @Override
    protected void onStop() {
        super.onStop();
        roomLivingViewModel.onStop();
    }

    @Override
    public boolean isBlackDarkStatus() {
        return false;
    }

    private Runnable toggleVideoRun;

    //开启 关闭摄像头
    private void toggleSelfVideo(boolean isOpen) {
        toggleVideoRun = () -> roomLivingViewModel.toggleSelfVideo(isOpen ? 1 : 0);
        requestCameraPermission();
    }

    @Override
    public void getPermissions() {
        if (toggleVideoRun != null) {
            toggleVideoRun.run();
            toggleVideoRun = null;
        }
        // TODO ?
//        VLRoomSeatModel seatLocal = roomLivingViewModel.seatLocalLiveData.getValue();
//        if (seatLocal != null && seatLocal.isSelfMuted() == 0) {
//            RTCManager.getInstance().getRtcEngine().disableAudio();
//            RTCManager.getInstance().getRtcEngine().enableAudio();
//        }
    }

    private void onMemberLeave(@NonNull VLRoomSeatModel member) {
        if (member.getUserNo().equals(UserManager.getInstance().getUser().userNo)) {
            getBinding().groupBottomView.setVisibility(View.GONE);
            getBinding().groupEmptyPrompt.setVisibility(View.VISIBLE);
        }
        VLRoomSeatModel temp = mRoomSpeakerAdapter.getItemData(member.getSeatIndex());
        if (temp != null) {
            mRoomSpeakerAdapter.dataList.set(member.getSeatIndex(), null);
            mRoomSpeakerAdapter.notifyItemChanged(member.getSeatIndex());
        }
    }

    private void showCreatorExitDialog() {
        if (creatorExitDialog == null) {
            creatorExitDialog = new CloseRoomDialog(this);
            creatorExitDialog.setCanceledOnTouchOutside(false);
            creatorExitDialog.setOnButtonClickListener(new OnButtonClickListener() {
                @Override
                public void onLeftButtonClick() {
                    setDarkStatusIcon(isBlackDarkStatus());
                    finish();
                }

                @Override
                public void onRightButtonClick() {
                    setDarkStatusIcon(isBlackDarkStatus());
                    finish();

                }
            });
        }
        creatorExitDialog.show();
    }

    private void showLoadingDialog(boolean show) {
        if (mLoadingDialog == null) {
            mLoadingDialog = new ProgressDialog(this);
            mLoadingDialog.setMessage(getString(R.string.loading));
        }
        if (show) {
            mLoadingDialog.show();
        } else {
            mLoadingDialog.dismiss();
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        roomLivingViewModel.release();
    }

    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK) {
            showExitDialog();
            return true;
        }
        return super.onKeyDown(keyCode, event);
    }
}
