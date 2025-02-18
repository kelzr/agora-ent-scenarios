//
//  VRSoundEffectsCell.swift
//  VoiceRoomBaseUIKit
//
//  Created by 朱继超 on 2022/8/26.
//

import UIKit
import ZSwiftBaseLib

public class SASoundEffectsCell: UITableViewCell, UICollectionViewDelegate, UICollectionViewDataSource {
    var entity: SARoomMenuBarEntity?

    private var images = [["wangyi", "momo", "pipi", "yinyu"], ["wangyi", "jiamian", "yinyu", "paipaivoice", "wanba", "qingtian", "skr", "soul"], ["yalla-ludo", "jiamian"], ["qingmang", "cowLive", "yuwan", "weibo"]]

    lazy var background: UIView = .init(frame: CGRect(x: 20, y: 15, width: ScreenWidth - 40, height: self.frame.height - 15)).backgroundColor(.white).cornerRadius(20)

    lazy var shaodw: UIView = .init(frame: CGRect(x: 32, y: 17, width: ScreenWidth - 64, height: self.frame.height - 15)).backgroundColor(.white)

    lazy var effectName: UILabel = .init(frame: CGRect(x: 20, y: 17.5, width: self.background.frame.width - 40, height: 20)).textColor(UIColor(0x156EF3)).font(.systemFont(ofSize: 16, weight: .semibold))

    lazy var effectDesc: UILabel = .init(frame: CGRect(x: 20, y: self.effectName.frame.maxY + 4, width: self.effectName.frame.width, height: 60)).font(.systemFont(ofSize: 13, weight: .regular)).textColor(UIColor(0x3C4267)).numberOfLines(0)

    lazy var line: UIView = .init(frame: CGRect(x: 20, y: self.effectDesc.frame.maxY + 6, width: self.effectDesc.frame.width, height: 1)).backgroundColor(UIColor(0xF6F6F6))

    lazy var customUsage: UILabel = .init(frame: CGRect(x: 20, y: self.effectDesc.frame.maxY + 10, width: 200, height: 15)).font(.systemFont(ofSize: 11, weight: .regular)).textColor(UIColor(0xD8D8D8)).text(sceneLocalized( "Current Customer Usage"))

    lazy var flowLayout: UICollectionViewFlowLayout = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 10
        layout.itemSize = CGSize(width: 20, height: 20)
        return layout
    }()

    lazy var iconList: UICollectionView = .init(frame: CGRect(x: 20, y: self.customUsage.frame.maxY + 5, width: self.effectName.frame.width, height: 20), collectionViewLayout: self.flowLayout).delegate(self).dataSource(self).registerCell(SAIconCell.self, forCellReuseIdentifier: "VRIconCell").showsVerticalScrollIndicator(false).showsHorizontalScrollIndicator(false).isUserInteractionEnabled(false).backgroundColor(.white)

    lazy var chooseSymbol: UIImageView = .init(frame: CGRect(x: self.background.frame.width - 32, y: self.frame.height - 31, width: 32, height: 31)).image(UIImage("dan-check")!).contentMode(.scaleAspectFit)

    override public init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.backgroundColor = .clear
        backgroundColor = .clear
        contentView.addSubview(shaodw)
        contentView.addSubview(background)
        shaodw.layer.shadowRadius = 8
        shaodw.layer.shadowOffset = CGSize(width: 0, height: 2)
        shaodw.layer.shadowColor = UIColor(red: 0.04, green: 0.1, blue: 0.16, alpha: 0.12).cgColor
        shaodw.layer.shadowOpacity = 1
        background.addSubViews([effectName, effectDesc, line, customUsage, iconList, chooseSymbol])
        iconList.isScrollEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension SASoundEffectsCell {
    static func items() -> [SARoomMenuBarEntity] {
        var items = [SARoomMenuBarEntity]()
        do {
            for dic in [["title": sceneLocalized( "Social Chat"), "detail": sceneLocalized( "This sound effect focuses on solving the voice call problem of the Social Chat scene, including noise cancellation and echo suppression of the anchor's voice. It can enable users of different network environments and models to enjoy ultra-low delay and clear and beautiful voice in multi-person chat."), "selected": true, "index": 0, "soundType": 1], ["title": sceneLocalized( "Karaoke"), "detail": sceneLocalized( "This sound effect focuses on solving all kinds of problems in the Karaoke scene of single-person or multi-person singing, including the balance processing of accompaniment and voice, the beautification of sound melody and voice line, the volume balance and real-time synchronization of multi-person chorus, etc. It can make the scenes of Karaoke more realistic and the singers' songs more beautiful."), "selected": false, "index": 1, "soundType": 2], ["title": sceneLocalized( "Gaming Buddy"), "detail": sceneLocalized( "This sound effect focuses on solving all kinds of problems in the game scene where the anchor plays with him, including the collaborative reverberation processing of voice and game sound, the melody of sound and the beautification of sound lines. It can make the voice of the accompanying anchor more attractive and ensure the scene feeling of the game voice. "), "selected": false, "index": 2, "soundType": 3], ["title": sceneLocalized( "Professional Podcaster"), "detail": sceneLocalized( "This sound effect focuses on solving the problems of poor sound quality of mono anchors and compatibility with mainstream external sound cards. The sound network stereo collection and high sound quality technology can greatly improve the sound quality of anchors using sound cards and enhance the attraction of live broadcasting rooms. At present, it has been adapted to mainstream sound cards in the market. "), "selected": false, "index": 3, "soundType": 4]] {
                let data = try JSONSerialization.data(withJSONObject: dic, options: [])
                let item = try JSONDecoder().decode(SARoomMenuBarEntity.self, from: data)
                items.append(item)
            }
        } catch {
            assertionFailure("\(error.localizedDescription)")
        }
        return items
    }

    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        images[entity?.index ?? 0].count
    }

    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "VRIconCell", for: indexPath) as? SAIconCell
        cell?.imageView.image = UIImage(images[entity?.index ?? 0][indexPath.row])
        return cell ?? UICollectionViewCell()
    }

    func refresh(item: SARoomMenuBarEntity) {
        entity = item
        effectName.text = item.title
        effectDesc.text = item.detail
        chooseSymbol.isHidden = !item.selected
        if item.selected {
            background.layerProperties(UIColor(0x009FFF), 1)
        } else {
            background.layerProperties(.clear, 1)
        }
        background.frame = CGRect(x: 20, y: 15, width: contentView.frame.width - 40, height: contentView.frame.height - 15)
        shaodw.frame = CGRect(x: 35, y: 15, width: contentView.frame.width - 70, height: frame.height - 16)
        effectName.frame = CGRect(x: 20, y: 15, width: background.frame.width - 40, height: 22)
        effectDesc.frame = CGRect(x: 20, y: effectName.frame.maxY + 4, width: effectName.frame.width, height: SASoundEffectsList.heightMap[item.title] ?? 60)
        line.frame = CGRect(x: 20, y: effectDesc.frame.maxY + 6, width: effectDesc.frame.width, height: 1)
        customUsage.frame = CGRect(x: 20, y: effectDesc.frame.maxY + 10, width: 200, height: 15)
        iconList.frame = CGRect(x: 20, y: Int(customUsage.frame.maxY) + 5, width: Int(background.frame.width) - 40, height: 20)
        chooseSymbol.frame = CGRect(x: background.frame.width - 32, y: background.frame.height - 31, width: 32, height: 31)
        iconList.reloadData()
    }
}

public class SAIconCell: UICollectionViewCell {
    lazy var imageView: UIImageView = .init(frame: CGRect(x: 0, y: 0, width: self.frame.width, height: self.frame.height)).contentMode(.scaleAspectFill)

    override public init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

//    public override func layoutSubviews() {
//        super.layoutSubviews()
//        self.imageView.frame = CGRect(x: 0, y: 0, width: self.frame.width, height: self.frame.height)
//    }
}
