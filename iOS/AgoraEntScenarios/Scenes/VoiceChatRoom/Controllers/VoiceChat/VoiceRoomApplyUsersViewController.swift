//
//  VoiceRoomApplyUsersViewController.swift
//  VoiceRoomBaseUIKit
//
//  Created by 朱继超 on 2022/9/11.
//

import SVProgressHUD
import UIKit
import ZSwiftBaseLib

public class VoiceRoomApplyUsersViewController: UITableViewController {
    
    private var apply: VoiceRoomApplyEntity?

    private var roomId: String?
    
    var agreeApply:((VRRoomMic) -> Void)?
    
    lazy var empty: VREmptyView = .init(frame: CGRect(x: 0, y: 0, width: ScreenWidth, height: 360), title: "No one raised hands yet", image: nil).backgroundColor(.white)

    public convenience init(roomId: String) {
        self.init()
        self.roomId = roomId
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.insertSubview(empty, belowSubview: tableView)
        tableView.tableFooterView(UIView()).registerCell(VoiceRoomApplyCell.self, forCellReuseIdentifier: "VoiceRoomApplyCell").rowHeight(73).backgroundColor(.white).separatorInset(edge: UIEdgeInsets(top: 72, left: 15, bottom: 0, right: 15)).separatorColor(UIColor(0xF2F2F2)).showsVerticalScrollIndicator(false).backgroundColor(.clear)
        tableView.refreshControl = UIRefreshControl()
        tableView.refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    // MARK: - Table view data source

    override public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        ChatRoomServiceImp.getSharedInstance().applicants.count 
    }

    override public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell = tableView.dequeueReusableCell(withIdentifier: "VoiceRoomApplyCell", for: indexPath) as? VoiceRoomApplyCell
        if cell == nil {
            cell = VoiceRoomApplyCell(style: .default, reuseIdentifier: "VoiceRoomApplyCell")
        }
        // Configure the cell...
        cell?.selectionStyle = .none
        cell?.refresh(item: ChatRoomServiceImp.getSharedInstance().applicants[safe: indexPath.row])
        cell?.agreeClosure = { [weak self] in
            self?.agreeUserApply(user: $0)
            ChatRoomServiceImp.getSharedInstance().applicants[safe: indexPath.row]?.member?.invited = true
            self?.tableView.reloadData()
        }
        return cell ?? VoiceRoomApplyCell()
    }

//    override public func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
//        if apply?.cursor != nil, (apply?.apply_list?.count ?? 0) - 2 == indexPath.row, (apply?.total ?? 0) >= (apply?.apply_list?.count ?? 0) {
//            fetchUsers()
//        }
//    }
}

extension VoiceRoomApplyUsersViewController {
    @objc func refresh() {
        ChatRoomServiceImp.getSharedInstance().fetchApplicantsList { error, applicants in
            self.refreshEnd()
            self.empty.isHidden = (applicants?.count ?? 0) > 0
        }
    }
    
    @objc func refreshEnd() {
        self.tableView.refreshControl?.endRefreshing()
        self.tableView.reloadData()
    }

    private func agreeUserApply(user: VoiceRoomApply?) {
        SVProgressHUD.show()
        guard let user1 = user?.member else { return }
        ChatRoomServiceImp.getSharedInstance().acceptMicSeatApply(chatUid: user1.chat_uid ?? "", completion: { error,mic  in
            SVProgressHUD.dismiss()
            if self.agreeApply != nil,let mic = mic {
                self.agreeApply!(mic)
            }
            self.tableView.reloadData()
            let warningMessage = (error == nil ? "Agree success!".localized():"Agree failed!".localized())
            self.view.makeToast(warningMessage)
        })
    }
}
