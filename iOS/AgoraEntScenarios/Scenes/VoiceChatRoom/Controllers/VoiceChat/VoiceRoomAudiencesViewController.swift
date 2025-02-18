//
//  VoiceRoomAudienceTableViewController.swift
//  VoiceRoomBaseUIKit
//
//  Created by 朱继超 on 2022/9/9.
//

import UIKit
import ZSwiftBaseLib

public final class VoiceRoomAudiencesViewController: UITableViewController {
    
    var datas: [VRUser]?
    
    var kickClosure: ((VRUser?,VRRoomMic?) -> ())?

    lazy var empty: VREmptyView = .init(frame: CGRect(x: 0, y: 10, width: ScreenWidth, height: self.view.frame.height - 10 - CGFloat(ZBottombarHeight) - 30), title: "No audience yet", image: nil)

    override public func viewDidLoad() {
        super.viewDidLoad()
        view.insertSubview(empty, belowSubview: tableView)
        tableView.tableFooterView(UIView()).registerCell(VoiceRoomAudienceCell.self, forCellReuseIdentifier: "VoiceRoomAudienceCell").rowHeight(73).backgroundColor(.white).showsVerticalScrollIndicator(false).separatorInset(edge: UIEdgeInsets(top: 72, left: 15, bottom: 0, right: 15)).separatorColor(UIColor(0xF2F2F2))
        tableView.refreshControl = UIRefreshControl()
        tableView.refreshControl?.addTarget(self, action: #selector(refresh), for: .valueChanged)
        self.refresh()
    }

    // MARK: - Table view data source

    override public func numberOfSections(in tableView: UITableView) -> Int {
        1
    }

    override public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        self.datas?.count ?? 0
    }

    override public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        var cell = tableView.dequeueReusableCell(withIdentifier: "VoiceRoomAudienceCell") as? VoiceRoomAudienceCell
        if cell == nil {
            cell = VoiceRoomAudienceCell(style: .default, reuseIdentifier: "VoiceRoomAudienceCell")
        }
        cell?.selectionStyle = .none
        cell?.refresh(user: self.datas?[safe: indexPath.row])
        cell?.actionClosure = {
            self.removeUser(user: $0)
        }
        return cell ?? VoiceRoomAudienceCell()
    }
}

extension VoiceRoomAudiencesViewController {
    
    @objc private func refresh() {
        ChatRoomServiceImp.getSharedInstance().fetchRoomMembers { error, users in
            if error == nil {
                self.refreshEnd()
                self.datas?.removeAll()
                self.datas = users
                self.empty.isHidden = ((self.datas?.count ?? 0) > 0)
                self.tableView.reloadData()
            }
            self.tableView.refreshControl?.endRefreshing()
        }
    }
    
    private func refreshEnd() {
        self.tableView.refreshControl?.endRefreshing()
        self.tableView.reloadData()
    }
    
    private func removeUser(user: VRUser) {
        VoiceRoomIMManager.shared?.kickUser(chat_uid: user.chat_uid ?? "", completion: { success in
            if success {
                var index = -1
                var status = -1
                for mic in ChatRoomServiceImp.getSharedInstance().mics {
                    if mic.member?.chat_uid ?? "" == user.chat_uid ?? "" {
                        index = mic.mic_index
                        status = mic.status
                        break
                    }
                }
                if index > 0,var mic = ChatRoomServiceImp.getSharedInstance().mics[safe: index]  {
                    mic.status = status
                    mic.member = nil
                    VoiceRoomIMManager.shared?.setChatroomAttributes( attributes: ["mic_\(index)":mic.kj.JSONString()], completion: { error in
                        if error == nil {
                            if self.kickClosure != nil  {
                                self.kickClosure!(user,mic)
                            }
                            self.removeUserFromUserList(user: user)
                        } else {
                            self.view.makeToast("kick failed!")
                        }
                    })
                } else {
                    self.removeUserFromUserList(user: user)
                    if self.kickClosure != nil  {
                        self.kickClosure!(user,nil)
                    }
                }
            }
        })
    }
    
    private func removeUserFromUserList(user: VRUser) {
        ChatRoomServiceImp.getSharedInstance().userList = ChatRoomServiceImp.getSharedInstance().userList?.filter({ $0.chat_uid ?? "" != user.chat_uid ?? ""
        })
        ChatRoomServiceImp.getSharedInstance().updateRoomMembers { error in
            if error == nil {
                self.view.makeToast("kick successful!")
                self.refresh()
            }
        }
    }
}
