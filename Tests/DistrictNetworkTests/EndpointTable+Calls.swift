@testable import DistrictNetwork
import Foundation

extension EndpointTable {
    static func core() -> [EndpointExpectation] {
        [
            EndpointExpectation(
                .workspaceList,
                DistrictEndpoints.workspaceList(),
                .get,
                "\(host)/api/district/workspace/list"
            ),
            EndpointExpectation(
                .overview,
                DistrictEndpoints.overview(workspaceId: "ws_1"),
                .get,
                "\(host)/api/district/overview?workspaceId=ws_1"
            ),
            EndpointExpectation(
                .stripeBilling,
                DistrictEndpoints.stripeBilling(),
                .get,
                "\(host)/api/billing"
            ),
            EndpointExpectation(
                .workspaceBilling,
                DistrictEndpoints.workspaceBilling(workspaceId: "ws_1"),
                .get,
                "\(host)/api/district/workspace/billing?workspaceId=ws_1"
            ),
        ]
    }

    static func callLog() -> [EndpointExpectation] {
        [
            EndpointExpectation(
                .calls,
                DistrictEndpoints.calls(workspaceId: "ws_1", limit: 25, offset: 50),
                .get,
                "\(host)/api/district/calls?workspaceId=ws_1&limit=25&offset=50"
            ),
            EndpointExpectation(
                .callDetail,
                DistrictEndpoints.callDetail(workspaceId: "ws_1", callId: "call_1"),
                .get,
                "\(host)/api/district/calls/call_1?workspaceId=ws_1"
            ),
            EndpointExpectation(
                .callTranscript,
                DistrictEndpoints.callTranscript(workspaceId: "ws_1", callId: "call_1"),
                .get,
                "\(host)/api/district/calls/call_1/transcript?workspaceId=ws_1"
            ),
            // ⚠️ IN `telephony()` BY RIGHT, HERE FOR ITS LINE BUDGET. The call in the
            // path (hyphenated route), the workspace and the hex token in the body.
            EndpointExpectation(
                .registerLiveActivity,
                DistrictEndpoints.registerLiveActivity(workspaceId: "ws_1", callId: "call_1", token: "ab01"),
                .post,
                "\(host)/api/district/calls/call_1/live-activity",
                .json(#"{"token":"ab01","workspaceId":"ws_1"}"#)
            ),
            // ⚠️ NO CALL: the start token is the user's, under `live-activity/`.
            EndpointExpectation(
                .registerLiveActivityStartToken,
                DistrictEndpoints.registerLiveActivityStartToken(workspaceId: "ws_1", token: "cd02"),
                .post,
                "\(host)/api/district/live-activity/start-token",
                .json(#"{"token":"cd02","workspaceId":"ws_1"}"#)
            ),
        ]
    }

    static func telephony() -> [EndpointExpectation] {
        [
            EndpointExpectation(
                .dial,
                DistrictEndpoints.dial(workspaceId: "ws_1", to: "+15555550123"),
                .post,
                "\(host)/api/district/calls/dial",
                .json(#"{"to":"+15555550123","workspaceId":"ws_1"}"#)
            ),
            EndpointExpectation(
                .answerCall,
                DistrictEndpoints.answerCall(callId: "call_1", workspaceId: "ws_1"),
                .post,
                "\(host)/api/district/calls/call_1/answer",
                .json(#"{"workspaceId":"ws_1"}"#)
            ),
            // ⛔ ONE SEGMENT FROM `dial` AND GOVERNED BY THE OPPOSITE RULE: this one
            // is idempotent and is deliberately sent on endings that may have sent
            // it already. See ``DistrictEndpoints/hangUpCall(callId:workspaceId:)``.
            // ⛔ SENT ONLY ON A PERSON'S DECLINE; the call is in the path and the
            // workspace in the body, exactly like `answer`.
            EndpointExpectation(
                .declineCall,
                DistrictEndpoints.declineCall(callId: "call_1", workspaceId: "ws_1"),
                .post,
                "\(host)/api/district/calls/call_1/decline",
                .json(#"{"workspaceId":"ws_1"}"#)
            ),
            // ⛔ NO ID IN THE PATH: the call travels in the body as `callId`, and the
            // line under the key `whisper`.
            EndpointExpectation(
                .whisper,
                DistrictEndpoints.whisper(workspaceId: "ws_1", callId: "call_1", text: "Ask what the call is about."),
                .post,
                "\(host)/api/district/calls/whisper",
                .json(#"{"callId":"call_1","whisper":"Ask what the call is about.","workspaceId":"ws_1"}"#)
            ),
            EndpointExpectation(
                .hangUpCall,
                DistrictEndpoints.hangUpCall(callId: "call_1", workspaceId: "ws_1"),
                .post,
                "\(host)/api/district/calls/call_1/hangup",
                .json(#"{"workspaceId":"ws_1"}"#)
            ),
            EndpointExpectation(
                .roomToken,
                DistrictEndpoints.roomToken(roomName: meetingRoom),
                .post,
                "\(host)/api/district/calls/token",
                .json(#"{"identity":"ios","roomName":"meet_standup"}"#)
            ),
            EndpointExpectation(
                .meetings,
                DistrictEndpoints.meetings(workspaceId: "ws_1"),
                .get,
                "\(host)/api/district/meetings?workspaceId=ws_1"
            ),
            EndpointExpectation(
                .meetingDetail,
                DistrictEndpoints.meetingDetail(workspaceId: "ws_1", meetingId: "m_1"),
                .get,
                "\(host)/api/district/meetings/m_1?workspaceId=ws_1"
            ),
        ]
    }
}
