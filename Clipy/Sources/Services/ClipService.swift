//
//  ClipService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/11/17.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import Cocoa
import RealmSwift
import PINCache
import RxSwift
import RxCocoa

final class ClipService {

    // MARK: - Properties
    fileprivate var cachedChangeCount = BehaviorRelay<Int>(value: 0)
    fileprivate var storeTypes = [String: NSNumber]()
    fileprivate let scheduler = SerialDispatchQueueScheduler(qos: .userInteractive)
    fileprivate let lock = NSRecursiveLock(name: "com.clipy-app.Clipy.ClipUpdatable")
    fileprivate var disposeBag = DisposeBag()

    // MARK: - Clips
    func startMonitoring() {
        disposeBag = DisposeBag()
        // Pasteboard observe timer
        Observable<Int>.interval(.milliseconds(200), scheduler: scheduler)
            .map { _ in NSPasteboard.general.changeCount }
            .withLatestFrom(cachedChangeCount.asObservable()) { ($0, $1) }
            .filter { $0 != $1 }
            .subscribe(onNext: { [weak self] changeCount, _ in
                guard let self else { return }
                if self.create() {
                    self.cachedChangeCount.accept(changeCount)
                }
            })
            .disposed(by: disposeBag)
        // Store types
        AppEnvironment.current.defaults.rx
            .observe([String: NSNumber].self, Constants.UserDefaults.storeTypes)
            .compactMap { $0 }
            .asDriver(onErrorDriveWith: .empty())
            .drive(onNext: { [weak self] in
                self?.storeTypes = $0
            })
            .disposed(by: disposeBag)
    }

    func clearAll() {
        let realm = try! Realm()
        let clips = realm.objects(CPYClip.self)

        // Delete saved images
        clips
            .filter { !$0.thumbnailPath.isEmpty }
            .map { $0.thumbnailPath }
            .forEach { PINCache.shared.removeObject(forKey: $0) }
        // Delete Realm
        realm.transaction { realm.delete(clips) }
        // Delete writed datas
        AppEnvironment.current.dataCleanService.cleanDatas()
    }

    func delete(with clip: CPYClip) {
        let realm = try! Realm()
        // Delete saved images
        let path = clip.thumbnailPath
        if !path.isEmpty {
            PINCache.shared.removeObject(forKey: path)
        }
        // Delete Realm
        realm.transaction { realm.delete(clip) }
    }

    func incrementChangeCount() {
        cachedChangeCount.accept(cachedChangeCount.value + 1)
    }

    func syncChangeCountToPasteboard() {
        cachedChangeCount.accept(NSPasteboard.general.changeCount)
    }

    func markAsRecentlyUsed(_ clip: CPYClip) {
        guard AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.reorderClipsAfterPasting) else { return }

        let realm = try! Realm()
        guard let savedClip = realm.object(ofType: CPYClip.self, forPrimaryKey: clip.dataHash), !savedClip.isInvalidated else { return }

        realm.transaction {
            savedClip.updateTime = Int(Date().timeIntervalSince1970 * 1000)
        }
    }

}

// MARK: - Create Clip
extension ClipService {
    fileprivate func create() -> Bool {
        lock.lock(); defer { lock.unlock() }

        // Store types
        if !storeTypes.values.contains(NSNumber(value: true)) { return true }
        // Pasteboard types
        let pasteboard = NSPasteboard.general
        let types = self.types(with: pasteboard)
        if types.isEmpty { return false }

        // Excluded application
        guard !AppEnvironment.current.excludeAppService.frontProcessIsExcludedApplication() else { return true }
        // Special applications
        guard !AppEnvironment.current.excludeAppService.copiedProcessIsExcludedApplications(pasteboard: pasteboard) else { return true }

        // Create data
        let data = CPYClipData(pasteboard: pasteboard, types: types)
        return save(with: data, sourceApplication: copySourceApplication())
    }

    /// 复制发生时的前台应用即为内容来源。Clipy 自身窗口（如片段编辑器）处于前台时，
    /// 回退到 ExcludeAppService 跟踪到的上一个前台应用，避免把来源记成 Clipy 自己。
    fileprivate func copySourceApplication() -> NSRunningApplication? {
        let ownBundleIdentifier = Bundle.main.bundleIdentifier
        if let frontApplication = NSWorkspace.shared.frontmostApplication,
           frontApplication.bundleIdentifier != ownBundleIdentifier {
            return frontApplication
        }
        if let lastApplication = AppEnvironment.current.excludeAppService.lastFrontApplication,
           lastApplication.bundleIdentifier != ownBundleIdentifier {
            return lastApplication
        }
        return nil
    }

    func create(with image: NSImage) {
        lock.lock(); defer { lock.unlock() }

        // Create only image data
        let data = CPYClipData(image: image)
        _ = save(with: data)
    }

    fileprivate func save(with data: CPYClipData, sourceApplication: NSRunningApplication? = nil) -> Bool {
        if !data.hasMeaningfulContent { return false }
        // Don't save empty string history
        if data.isOnlyStringType && data.stringValue.isEmpty { return false }

        let realm = try! Realm()
        // 内容指纹：以内容本身计算的稳定 hash 作为主键。相同内容必然得到相同主键，
        // Realm 对主键建立唯一索引，查重为 O(1) 哈希查找，无需遍历历史，数据量再大也是常数时间。
        let contentHash = "\(data.hash)"

        // 已存在相同内容 → 去重，绝不产生重复条目
        if let existing = realm.object(ofType: CPYClip.self, forPrimaryKey: contentHash), !existing.isInvalidated {
            let isOverwriteHistory = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.overwriteSameHistory)
            let isCopySameHistory = AppEnvironment.current.defaults.bool(forKey: Constants.UserDefaults.copySameHistory)
            // 直接更新已存在的记录对象，isFavorite 等用户状态自然保留，不会被覆盖丢失
            if isOverwriteHistory || isCopySameHistory {
                realm.transaction {
                    existing.updateTime = Int(Date().timeIntervalSince1970 * 1000)
                    if isOverwriteHistory, let sourceApplication = sourceApplication {
                        existing.sourceBundleIdentifier = sourceApplication.bundleIdentifier ?? ""
                        existing.sourceAppName = sourceApplication.localizedName ?? ""
                    }
                }
            }
            return true
        }

        // 不存在相同内容 → 新建条目
        // Saved time and path
        let unixTime = Int(Date().timeIntervalSince1970 * 1000)
        let savedPath = CPYUtilities.applicationSupportFolder() + "/\(NSUUID().uuidString).data"
        // Create Realm object
        let clip = CPYClip()
        clip.dataPath = savedPath
        clip.title = data.titleText[0...10000]
        clip.dataHash = contentHash
        clip.updateTime = unixTime
        clip.primaryType = data.primaryType?.rawValue ?? ""
        if let sourceApplication = sourceApplication {
            clip.sourceBundleIdentifier = sourceApplication.bundleIdentifier ?? ""
            clip.sourceAppName = sourceApplication.localizedName ?? ""
        }

        // Save thumbnail image before Realm commit so menu refresh sees a complete record.
        if let thumbnailImage = data.thumbnailImage {
            PINCache.shared.setObject(thumbnailImage, forKey: "\(unixTime)")
            clip.thumbnailPath = "\(unixTime)"
        }
        if let colorCodeImage = data.colorCodeImage {
            PINCache.shared.setObject(colorCodeImage, forKey: "\(unixTime)")
            clip.thumbnailPath = "\(unixTime)"
            clip.isColorCode = true
        }

        if CPYUtilities.prepareSaveToPath(CPYUtilities.applicationSupportFolder()) &&
            NSKeyedArchiver.archiveRootObject(data, toFile: savedPath) {
            realm.transaction {
                realm.add(clip, update: .all)
            }
        }

        return true
    }

    private func types(with pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        let types = pasteboard.types?.filter { canSave(with: $0) } ?? []
        return NSOrderedSet(array: types).array as? [NSPasteboard.PasteboardType] ?? []
    }

    private func canSave(with type: NSPasteboard.PasteboardType) -> Bool {
        let dictionary = CPYClipData.availableTypesDictinary
        guard let value = dictionary[type] else { return false }
        guard let number = storeTypes[value] else { return false }
        return number.boolValue
    }
}
