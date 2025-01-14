//
//  SABusinessRequest.swift
//  SABaseUIKit-SABaseUIKit
//
//  Created by 朱继超 on 2022/8/29.
//

import KakaJSON
import UIKit
import ZSwiftBaseLib

public class SAError: Error, Convertible {
    var code: String?
    var message: String?

    public required init() {}

    public func kj_modelKey(from property: Property) -> ModelPropertyKey {
        property.name
    }
}

@objc public class SABusinessRequest: NSObject {
    @UserDefault("SABusinessUserToken", defaultValue: "") public var userToken

    @objc public static let shared = SABusinessRequest()

    public func changeHost(host: String) {
        SARequest.shared.configHost(url: host)
    }

    /// Description send a request contain generic
    /// - Parameters:
    ///   - method: SARequestHTTPMethod
    ///   - uri: The part spliced after the host.For example,"/xxx/xxx"
    ///   - params: body params
    ///   - callBack: response callback the tuple that made of generic and error.
    /// - Returns: Request task,what if you can determine its status or cancel it .
    @discardableResult
    public func sendRequest<T: Convertible>(
        method: SARequestHTTPMethod,
        uri: String,
        params: [String: Any],
        callBack: @escaping ((T?, Error?) -> Void)
    ) -> URLSessionTask? {
        print(params)

        let headers = ["Authorization": userToken, "Content-Type": "application/json"]
        let task = SARequest.shared.constructRequest(method: method, uri: uri, params: params, headers: headers) { data, response, error in
            DispatchQueue.main.async {
                if error == nil, response?.statusCode ?? 0 == 200 {
                    callBack(model(from: data?.z.toDictionary() ?? [:], type: T.self) as? T, error)
                } else {
                    if error == nil {
                        let someError = model(from: data?.z.toDictionary() ?? [:], type: SAError.self) as? Error
                        callBack(nil, someError)
                    } else {
                        callBack(nil, error)
                    }
                }
            }
        }
        return task
    }

    /// Description send a request
    /// - Parameters:
    ///   - method: SARequestHTTPMethod
    ///   - uri: The part spliced after the host.For example,"/xxx/xxx"
    ///   - params: body params
    ///   - callBack: response callback the tuple that made of dictionary and error.
    /// - Returns: Request task,what if you can determine its status or cancel it .
    @discardableResult
    public func sendRequest(
        method: SARequestHTTPMethod,
        uri: String,
        params: [String: Any],
        callBack: @escaping (([String: Any]?, Error?) -> Void)
    ) -> URLSessionTask? {
        let headers = ["Authorization": userToken, "Content-Type": "application/json"]
        let task = SARequest.shared.constructRequest(method: method, uri: uri, params: params, headers: headers) { data, response, error in
            if error == nil, response?.statusCode ?? 0 == 200 {
                callBack(data?.z.toDictionary(), nil)
            } else {
                if error == nil {
                    let someError = model(from: data?.z.toDictionary() ?? [:], type: SAError.self) as? Error
                    callBack(nil, someError)
                } else {
                    callBack(nil, error)
                }
            }
        }
        return task
    }
}

// MARK: - rest request

public extension SABusinessRequest {
    // MARK: - generic uri request

    /// Description send a get request contain generic
    /// - Parameters:
    ///   - uri: The part spliced after the host.For example,"/xxx/xxx"
    ///   - params:  body params
    ///   - callBack: response callback the tuple that made of generic and error.
    /// - Returns: Request task,what if you can determine its status or cancel it .
    @discardableResult
    func sendGETRequest<U: Convertible>(
        uri: String,
        params: [String: Any], classType: U.Type,
        callBack: @escaping ((U?, Error?) -> Void)
    ) -> URLSessionTask? {
        sendRequest(method: .get, uri: uri, params: params, callBack: callBack)
    }

    /// Description send a post request contain generic
    /// - Parameters:
    ///   - uri: The part spliced after the host.For example,"/xxx/xxx"
    ///   - params:  body params
    ///   - callBack: response callback the tuple that made of generic and error.
    /// - Returns: Request task,what if you can determine its status or cancel it .
    @discardableResult
    func sendPOSTRequest<U: Convertible>(
        uri: String, params: [String: Any], classType: U.Type,
        callBack: @escaping ((U?, Error?) -> Void)
    ) -> URLSessionTask? {
        sendRequest(method: .post, uri: uri, params: params, callBack: callBack)
    }

    /// Description send a put request contain generic
    /// - Parameters:
    ///   - uri: The part spliced after the host.For example,"/xxx/xxx"
    ///   - params:  body params
    ///   - callBack: response callback the tuple that made of generic and error.
    /// - Returns: Request task,what if you can determine its status or cancel it .
    @discardableResult
    func sendPUTRequest<U: Convertible>(
        uri: String, params: [String: Any], classType: U.Type,
        callBack: @escaping ((U?, Error?) -> Void)
    ) -> URLSessionTask? {
        sendRequest(method: .put, uri: uri, params: params, callBack: callBack)
    }

    /// Description send a delete request contain generic
    /// - Parameters:
    ///   - uri: The part spliced after the host.For example,"/xxx/xxx"
    ///   - params:  body params
    ///   - callBack: response callback the tuple that made of generic and error.
    /// - Returns: Request task,what if you can determine its status or cancel it .
    @discardableResult
    func sendDELETERequest<U: Convertible>(
        uri: String, params: [String: Any], classType: U.Type,
        callBack: @escaping ((U?, Error?) -> Void)
    ) -> URLSessionTask? {
        sendRequest(method: .delete, uri: uri, params: params, callBack: callBack)
    }

    // MARK: - generic api request

    /// Description send a get request contain generic
    /// - Parameters:
    ///   - api: The part spliced after the host.For example,"/xxx/xxx".Package with SABusinessApi.
    ///   - params:  body params
    ///   - callBack: response callback the tuple that made of generic and error.
    /// - Returns: Request task,what if you can determine its status or cancel it .
    @discardableResult
    func sendGETRequest<U: Convertible>(
        api: SABusinessApi,
        params: [String: Any], classType: U.Type,
        callBack: @escaping ((U?, Error?) -> Void)
    ) -> URLSessionTask? {
        sendRequest(method: .get, uri: convertApi(api: api), params: params, callBack: callBack)
    }

    /// Description send a post request contain generic
    /// - Parameters:
    ///   - api: The part spliced after the host.For example,"/xxx/xxx".Package with SABusinessApi.
    ///   - params:  body params
    ///   - callBack: response callback the tuple that made of generic and error.
    /// - Returns: Request task,what if you can determine its status or cancel it .
    @discardableResult
    func sendPOSTRequest<U: Convertible>(
        api: SABusinessApi,
        params: [String: Any], classType: U.Type,
        callBack: @escaping ((U?, Error?) -> Void)
    ) -> URLSessionTask? {
        sendRequest(method: .post, uri: convertApi(api: api), params: params, callBack: callBack)
    }

    /// Description send a put request contain generic
    /// - Parameters:
    ///   - api: The part spliced after the host.For example,"/xxx/xxx".Package with SABusinessApi.
    ///   - params:  body params
    ///   - callBack: response callback the tuple that made of generic and error.
    /// - Returns: Request task,what if you can determine its status or cancel it .
    @discardableResult
    func sendPUTRequest<U: Convertible>(
        api: SABusinessApi,
        params: [String: Any], classType: U.Type,
        callBack: @escaping ((U?, Error?) -> Void)
    ) -> URLSessionTask? {
        sendRequest(method: .put, uri: convertApi(api: api), params: params, callBack: callBack)
    }

    /// Description send a delete request contain generic
    /// - Parameters:
    ///   - api: The part spliced after the host.For example,"/xxx/xxx".Package with SABusinessApi.
    ///   - params:  body params
    ///   - callBack: response callback the tuple that made of generic and error.
    /// - Returns: Request task,what if you can determine its status or cancel it .
    @discardableResult
    func sendDELETERequest<U: Convertible>(
        api: SABusinessApi,
        params: [String: Any], classType: U.Type,
        callBack: @escaping ((U?, Error?) -> Void)
    ) -> URLSessionTask? {
        sendRequest(method: .delete, uri: convertApi(api: api), params: params, callBack: callBack)
    }

    // MARK: - no generic uri request

    /// Description send a get request
    /// - Parameters:
    ///   - method: SARequestHTTPMethod
    ///   - uri: The part spliced after the host.For example,"/xxx/xxx"
    ///   - params: body params
    ///   - callBack: response callback the tuple that made of dictionary and error.
    /// - Returns: Request task,what if you can determine its status or cancel it .
    @discardableResult
    @objc
    func sendGETRequest(
        uri: String,
        params: [String: Any],
        callBack: @escaping (([String: Any]?, Error?) -> Void)
    ) -> URLSessionTask? {
        sendRequest(method: .get, uri: uri, params: params, callBack: callBack)
    }

    /// Description send a post request
    /// - Parameters:
    ///   - method: SARequestHTTPMethod
    ///   - uri: The part spliced after the host.For example,"/xxx/xxx"
    ///   - params: body params
    ///   - callBack: response callback the tuple that made of dictionary and error.
    /// - Returns: Request task,what if you can determine its status or cancel it .
    @discardableResult
    @objc
    func sendPOSTRequest(
        uri: String,
        params: [String: Any],
        callBack: @escaping (([String: Any]?, Error?) -> Void)
    ) -> URLSessionTask? {
        sendRequest(method: .post, uri: uri, params: params, callBack: callBack)
    }

    /// Description send a put request
    /// - Parameters:
    ///   - method: SARequestHTTPMethod
    ///   - uri: The part spliced after the host.For example,"/xxx/xxx"
    ///   - params: body params
    ///   - callBack: response callback the tuple that made of dictionary and error.
    /// - Returns: Request task,what if you can determine its status or cancel it .
    @discardableResult
    @objc
    func sendPUTRequest(
        uri: String,
        params: [String: Any],
        callBack: @escaping (([String: Any]?, Error?) -> Void)
    ) -> URLSessionTask? {
        sendRequest(method: .put, uri: uri, params: params, callBack: callBack)
    }

    /// Description send a delete request
    /// - Parameters:
    ///   - method: SARequestHTTPMethod
    ///   - uri: The part spliced after the host.For example,"/xxx/xxx"
    ///   - params: body params
    ///   - callBack: response callback the tuple that made of dictionary and error.
    /// - Returns: Request task,what if you can determine its status or cancel it .
    @discardableResult
    @objc
    func sendDELETERequest(
        uri: String,
        params: [String: Any],
        callBack: @escaping (([String: Any]?, Error?) -> Void)
    ) -> URLSessionTask? {
        sendRequest(method: .delete, uri: uri, params: params, callBack: callBack)
    }

    // MARK: - no generic api request

    /// Description send a get request
    /// - Parameters:
    ///   - api: The part spliced after the host.For example,"/xxx/xxx".Package with SABusinessApi.
    ///   - params:  body params
    ///   - callBack: response callback the tuple that made of generic and error.
    /// - Returns: Request task,what if you can determine its status or cancel it .
    @discardableResult
    func sendGETRequest(
        api: SABusinessApi,
        params: [String: Any],
        callBack: @escaping (([String: Any]?, Error?) -> Void)
    ) -> URLSessionTask? {
        sendRequest(method: .get, uri: convertApi(api: api), params: params, callBack: callBack)
    }

    /// Description send a post request
    /// - Parameters:
    ///   - api: The part spliced after the host.For example,"/xxx/xxx".Package with SABusinessApi.
    ///   - params:  body params
    ///   - callBack: response callback the tuple that made of generic and error.
    /// - Returns: Request task,what if you can determine its status or cancel it .
    @discardableResult
    func sendPOSTRequest(
        api: SABusinessApi,
        params: [String: Any],
        callBack: @escaping (([String: Any]?, Error?) -> Void)
    ) -> URLSessionTask? {
        sendRequest(method: .post, uri: convertApi(api: api), params: params, callBack: callBack)
    }

    /// Description send a put request
    /// - Parameters:
    ///   - api: The part spliced after the host.For example,"/xxx/xxx".Package with SABusinessApi.
    ///   - params:  body params
    ///   - callBack: response callback the tuple that made of generic and error.
    /// - Returns: Request task,what if you can determine its status or cancel it .
    @discardableResult
    func sendPUTRequest(
        api: SABusinessApi,
        params: [String: Any],
        callBack: @escaping (([String: Any]?, Error?) -> Void)
    ) -> URLSessionTask? {
        sendRequest(method: .put, uri: convertApi(api: api), params: params, callBack: callBack)
    }

    /// Description send a delete request
    /// - Parameters:
    ///   - api: The part spliced after the host.For example,"/xxx/xxx".Package with SABusinessApi.
    ///   - params:  body params
    ///   - callBack: response callback the tuple that made of generic and error.
    /// - Returns: Request task,what if you can determine its status or cancel it .
    @discardableResult
    func sendDELETERequest(
        api: SABusinessApi,
        params: [String: Any],
        callBack: @escaping (([String: Any]?, Error?) -> Void)
    ) -> URLSessionTask? {
        sendRequest(method: .delete, uri: convertApi(api: api), params: params, callBack: callBack)
    }

    /// Description convert api to uri
    /// - Parameter api: SABusinessApi
    /// - Returns: uri string
    func convertApi(api: SABusinessApi) -> String {
        var uri = "/voice/room"
        switch api {
        case .login:
            uri = "/user/login/device"
        case let .fetchRoomList(cursor, pageSize, type):
            uri += "/list?limit=\(pageSize)"
            if !cursor.isEmpty {
                uri += "&cursor=\(cursor)"
            }
            if type != nil, let idx = type {
                uri += "&type=\(idx)"
            }
        case .createRoom:
            uri += "/create"
        case let .fetchRoomInfo(roomId):
            uri += "/\(roomId)"
        case let .deleteRoom(roomId):
            uri += "/\(roomId)"
        case let .modifyRoomInfo(roomId):
            uri += "/\(roomId)"
        case let .fetchRoomMembers(roomId, cursor, pageSize):
            if cursor.isEmpty {
                uri += "/\(roomId)" + "/members/list?limit=\(pageSize)"
            } else {
                uri += "/\(roomId)" + "/members/list?limit=\(pageSize)&cursor=\(cursor)"
            }
        case let .validatePassWord(roomId):
            uri += "/\(roomId)" + "/validPassword"
        case let .joinRoom(roomId):
            uri += "/\(roomId)" + "/members/join"
        case let .leaveRoom(roomId):
            uri += "/\(roomId)" + "/members/leave"
        case let .kickUser(roomId):
            uri += "/\(roomId)" + "/members/kick"
        case let .fetchGiftContribute(roomId):
            uri += "/\(roomId)/gift/list"
        case let .giftTo(roomId):
            uri += "/\(roomId)/gift/add"
        case let .fetchApplyMembers(roomId, cursor, pageSize):
            if cursor.isEmpty {
                uri += "/\(roomId)" + "/mic/apply?limit=\(pageSize)"
            } else {
                uri += "/\(roomId)" + "/mic/apply?limit=\(pageSize)&cursor=\(cursor)"
            }
        case let .submitApply(roomId):
            uri += "/\(roomId)" + "/mic/apply"
        case let .cancelApply(roomId):
            uri += "/\(roomId)" + "/mic/apply"
        case let .agreeApply(roomId):
            uri += "/\(roomId)" + "/mic/apply/agree"
        case let .refuseApply(roomId):
            uri += "/\(roomId)" + "/mic/apply/refuse"
        case let .fetchMicsInfo(roomId):
            uri += roomId + "/mic"
        case let .closeMic(roomId):
            uri += "/\(roomId)" + "/mic/close"
        case let .cancelCloseMic(roomId, index):
            uri += "/\(roomId)" + "/mic/close?mic_index=\(index)"
        case let .leaveMic(roomId, index):
            uri += "/\(roomId)" + "/mic/leave?mic_index=\(index)"
        case let .muteMic(roomId):
            uri += "/\(roomId)" + "/mic/mute"
        case let .unmuteMic(roomId, index):
            uri += "/\(roomId)" + "/mic/mute?mic_index=\(index)"
        case let .exchangeMic(roomId):
            uri += "/\(roomId)" + "/mic/exchange"
        case let .kickMic(roomId):
            uri += "/\(roomId)" + "/mic/kick"
        case let .lockMic(roomId):
            uri += "/\(roomId)" + "/mic/lock"
        case let .unlockMic(roomId, index):
            uri += "/\(roomId)" + "/mic/lock?mic_index=\(index)"
        case let .inviteUserToMic(roomId):
            uri += "/\(roomId)" + "/mic/invite"
        case let .agreeInvite(roomId):
            uri += "/\(roomId)" + "/mic/invite/agree"
        case let .refuseInvite(roomId):
            uri += "/\(roomId)" + "/mic/invite/refuse"
        }
        return uri
    }
}
