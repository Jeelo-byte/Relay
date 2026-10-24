import Foundation
import SwiftUI
import LocalAuthentication

@MainActor public final class RelayStore:ObservableObject {
    @Published public var agreements:[Agreement]=[]
    @Published public var messages:[ChatMessage]=[]
    @Published public var rooms:[ChatRoom]=[]
    @Published public var session:AccountSession?
    @Published public var isDemo=false
    @Published public var started=false
    @Published public var locked=false
    @Published public var syncing=false
    @Published public var syncStatus="On This Device"
    @Published public var error:String?
    @Published public var toast:String?
    @Published public var syncIssues=0
    @Published public var processing=false
    @Published public var matrixStatus="Not Connected"
    public let deviceID:UUID
    private var local:LocalStore?
    private var syncTask:Task<Void,Never>?
    private let chatRecord=UUID(uuidString:"00000000-0000-4000-8000-000000000001")!
    private let roomsRecord=UUID(uuidString:"00000000-0000-4000-8000-000000000002")!
    public init() {
        deviceID=UUID(uuidString:UserDefaults.standard.string(forKey:"relay.device") ?? "") ?? UUID();UserDefaults.standard.set(deviceID.uuidString,forKey:"relay.device")
        do {local=try LocalStore();for id in try local!.ids() where id != chatRecord && id != roomsRecord {if let a=try local!.load(Agreement.self,id:id){agreements.append(a)}};messages=try local!.load([ChatMessage].self,id:chatRecord) ?? [];rooms=try local!.load([ChatRoom].self,id:roomsRecord) ?? [];isDemo=(try local!.meta("demo"))=="true";started=(try local!.meta("started"))=="true"
            if let data=try KeychainStore.read("account-session") {session=try JSONDecoder().decode(AccountSession.self,from:data);locked=true;syncStatus="Locked"}
        } catch {self.error=error.localizedDescription}
        if ProcessInfo.processInfo.arguments.contains("-demo") && !started {loadDemo()}
    }
    public var visible:[Agreement] {agreements.filter{$0.review_state != .dismissed}}
    public var dismissed:[Agreement] {agreements.filter{$0.review_state == .dismissed}}
    public var pendingCount:Int {(try? local?.dirtyIDs().filter{$0 != chatRecord && $0 != roomsRecord}.count) ?? 0}
    public func beginManual() {started=true;try? local?.setMeta("started",value:"true")}
    public func loadDemo() {
        guard agreements.isEmpty else {isDemo=true;beginManual();return}
        isDemo=true;beginManual();rooms=DemoData.rooms;messages=DemoData.messages;try? local?.setMeta("demo",value:"true");cacheChats();for a in DemoData.agreements {save(a)};toast="Sample workspace is ready"
    }
    public func save(_ a:Agreement) {
        var value=a;value.updated_at=Clock.ms
        do {try local?.save(value,id:value.id);if let i=agreements.firstIndex(where:{$0.id==a.id}) {agreements[i]=value}else{agreements.insert(value,at:0)};scheduleSync()}catch{self.error=error.localizedDescription}
    }
    public func accept(_ id:UUID) {mutate(id){a in a.review_state = .accepted;a.timeline.append(TimelineEvent("accepted"))};toast="Agreement Accepted"}
    public func dismiss(_ id:UUID) {mutate(id){a in a.review_state = .dismissed;a.timeline.append(TimelineEvent("dismissed"))};toast="Agreement Dismissed"}
    public func restore(_ id:UUID) {mutate(id){a in a.review_state = .suggested;a.timeline.append(TimelineEvent("restored"))};toast="Restored for Review"}
    public func done(_ id:UUID) {mutate(id){a in guard a.review_state == .accepted else{return};a.lifecycle = .fulfilled;for i in a.obligations.indices {a.obligations[i].status="done";a.obligations[i].done_at=Clock.ms};a.timeline.append(TimelineEvent("status_changed"))};toast="Marked Done"}
    public func toggleObligation(_ agreement:UUID,_ obligation:UUID) {mutate(agreement){a in guard a.review_state == .accepted,let i=a.obligations.firstIndex(where:{$0.id==obligation}) else{return};let done=a.obligations[i].isOpen;a.obligations[i].status=done ? "done":"open";a.obligations[i].done_at=done ? Clock.ms:nil;a.lifecycle=a.obligations.allSatisfy{!$0.isOpen} ? .fulfilled:.agreed;a.timeline.append(TimelineEvent("user_edit",field:"obligations[\(i)].status"))}}
    public func applyChange(_ agreement:UUID,_ event:UUID,apply:Bool) {mutate(agreement){a in guard let i=a.timeline.firstIndex(where:{$0.id==event}),a.timeline[i].pending else{return};let e=a.timeline[i];a.timeline[i].pending=false
        if apply,let value=e.new {
            if e.field_path=="obligations[0].due",!a.obligations.isEmpty {a.obligations[0].due=Due(date:value,raw:value)}
            if e.field_path=="lifecycle",let lifecycle=Lifecycle(rawValue:value){a.lifecycle=lifecycle}
        };a.timeline.append(TimelineEvent(apply ? "term_change_applied":"term_change_rejected",field:e.field_path,old:e.old,new:e.new))};toast=apply ? "Change Applied":"Change Ignored"}
    public func demoChange(_ id:UUID) {guard isDemo else{return};mutate(id){a in let text="Actually, Monday works better for paying you back.";let message=ChatMessage(room:a.source_room_ids.first ?? DemoData.rooms[0].id,sender:a.counterparty ?? DemoData.maya,text:text,network:a.counterparty?.network ?? .telegram);self.messages.append(message);let evidence=Evidence(message:message,supports:["obligations[0].due"]);a.evidence.append(evidence);a.timeline.append(TimelineEvent("term_change_suggested",actor:"ai",field:"obligations[0].due",old:a.obligations.first?.due?.date,new:DemoData.date(9),pending:true,evidence:evidence.id))};cacheChats()}
    private func mutate(_ id:UUID,operation:(inout Agreement)->Void) {guard var a=agreements.first(where:{$0.id==id}) else{return};operation(&a);save(a)}
    public func totals(owedToYou:Bool)->[(String,Money)] {
        var values:[String:Money]=[:]
        for a in agreements where a.review_state == .accepted && a.isActive {
            for o in a.obligations where o.isOpen {
                guard let amount=o.amount,(!amount.derived || a.review_state == .accepted),amount.minor>=0 else{continue}
                let selfID=a.parties.first(where:{$0.is_self})?.id
                guard (owedToYou ? o.obligee_party_id:o.obligor_party_id)==selfID else{continue}
                if values[amount.currency] == nil {values[amount.currency]=Money(minor:0,currency:amount.currency,exponent:amount.exponent)};values[amount.currency]!.minor+=amount.minor
            }
        };return values.sorted{$0.key<$1.key}.map{($0.key,$0.value)}
    }
    public func connect(_ newSession:AccountSession)throws {
        // Sample data never silently joins a real account.
        if isDemo {for a in agreements {try local?.remove(a.id)};agreements=[];messages=[];rooms=[];isDemo=false;try local?.setMeta("demo",value:"false");cacheChats()}
        if session?.account_id != newSession.account_id {try local?.resetSync()}
        session=newSession;try KeychainStore.write(JSONEncoder().encode(newSession),key:"account-session");locked=false;beginManual();Task{await sync()}
    }
    public func lock() {if session != nil {locked=true;syncStatus="Locked"}}
    public func unlockBiometrically()async {
        let context=LAContext();var reason:NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,error:&reason) else {error="Use your account passphrase to unlock on this device.";return}
        do {if try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,localizedReason:"Unlock your Relay agreements") {locked=false;Task{await sync()}}}catch{self.error="Biometric unlock was cancelled. You can use your passphrase."}
    }
    public func signOut() {session=nil;KeychainStore.delete("account-session");agreements=[];messages=[];rooms=[];locked=false;started=false;syncStatus="On This Device";try? local?.setMeta("started",value:"false");toast="Signed Out"}
    public func cacheChats() {do{try local?.save(messages,id:chatRecord,dirty:false);try local?.save(rooms,id:roomsRecord,dirty:false)}catch{self.error=error.localizedDescription}}
    public func setOptIn(_ id:String,_ opted:Bool){if let i=rooms.firstIndex(where:{$0.id==id}){rooms[i].opted_in=opted;cacheChats()}}
    public func newFromMessage(_ m:ChatMessage)->Agreement {var a=Agreement(title:"New Agreement",parties:[.me,m.sender].reduce(into:[Party]()){if !$0.contains($1){$0.append($1)}},obligations:[Obligation(from:m.sender.id,to:Party.me.id,what:"")],review:.accepted);a.evidence=[Evidence(message:m,supports:["user_attached"])];a.covered_event_ids=[m.event_id];a.source_room_ids=[m.room_id];return a}
    public func scheduleSync(){guard session != nil else{return};syncTask?.cancel();syncTask=Task{try? await Task.sleep(for:.seconds(2));if !Task.isCancelled{await sync()}}}
    public func sync()async {
        guard let s=session,!locked,!syncing,let local else{return};syncing=true;syncStatus="Syncing…";defer{syncing=false}
        let api=APIClient(baseURL:s.baseURL,token:s.token)
        do {
            for id in try local.dirtyIDs() where id != chatRecord && id != roomsRecord {
                guard let a=agreements.first(where:{$0.id==id}) else{continue};let base=try local.version(id)
                do {let result=try await api.put(a,session:s,base:base);if let current=agreements.first(where:{$0.id==id}),current != a {try local.save(current,id:id,dirty:true,serverVersion:result.version)}else{try local.synced(id,version:result.version)}}
                catch let e as APIError where e.status==409 {
                    guard let remote=e.current else{throw e}
                    if remote.deleted {agreements.removeAll{$0.id==id};try local.remove(id);toast="Deleted on Another Device";continue}
                    guard let encoded=remote.envelope,let data=Data(base64URL:encoded) else{throw VaultError.invalidEnvelope}
                    let server=try JSONDecoder().decode(Agreement.self,from:RelayCrypto.open(data,dek:s.dek,account:s.account_id,row:id,version:remote.version,keyVersion:remote.key_version))
                    let merged=Merge.agreements(local:a,server:server);try local.save(merged,id:id,dirty:true,serverVersion:remote.version);if let i=agreements.firstIndex(where:{$0.id==id}){agreements[i]=merged}
                    let result=try await api.put(merged,session:s,base:remote.version);try local.synced(id,version:result.version)
                }
            }
            var since=Int64(try local.meta("since") ?? "0") ?? 0;var more=true
            while more {let pull=try await api.pull(since:since)
                for row in pull.items {
                    if row.version <= (try local.version(row.row_id)){continue}
                    if row.deleted {try local.remove(row.row_id);agreements.removeAll{$0.id==row.row_id};continue}
                    do {guard let text=row.envelope,let data=Data(base64URL:text) else{throw VaultError.invalidEnvelope};let plain=try RelayCrypto.open(data,dek:s.dek,account:s.account_id,row:row.row_id,version:row.version,keyVersion:row.key_version);let a=try JSONDecoder().decode(Agreement.self,from:plain);guard a.id==row.row_id,a.schema=="relay.agreement/1" else{throw VaultError.unsupportedVersion};try local.save(a,id:a.id,dirty:false,serverVersion:row.version);if let i=agreements.firstIndex(where:{$0.id==a.id}){agreements[i]=a}else{agreements.append(a)}}catch{syncIssues+=1}
                };since=pull.next_since;try local.setMeta("since",value:String(since));more=pull.has_more
            };syncStatus=pendingCount==0 ? "Synced":"Changes Waiting"
        }catch {syncStatus="Not Synced";if let e=error as? APIError,e.code=="device_revoked" {signOut();self.error="This device was removed. Local account access has been cleared."}else{self.error=error.localizedDescription}}
    }
}
public enum Merge {
    public static func agreements(local:Agreement,server:Agreement)->Agreement {
        var a=server
        let rank:[ReviewState:Int]=[.suggested:0,.accepted:1,.dismissed:2]
        if rank[local.review_state,default:0]>rank[server.review_state,default:0]{a.review_state=local.review_state}
        var events=Dictionary(uniqueKeysWithValues:server.timeline.map{($0.id,$0)});for e in local.timeline where events[e.id]==nil{events[e.id]=e};a.timeline=events.values.sorted{$0.at<$1.at}
        if local.title != server.title || local.obligations != server.obligations {a.timeline.append(TimelineEvent("user_edit",field:"conflict",old:local.title,new:server.title))}
        var sources=Dictionary(uniqueKeysWithValues:server.evidence.map{($0.id,$0)});for e in local.evidence where sources[e.id]==nil {sources[e.id]=e};a.evidence=sources.values.sorted{$0.ts<$1.ts};a.covered_event_ids=Array(Set(server.covered_event_ids+local.covered_event_ids)).sorted();a.source_room_ids=Array(Set(server.source_room_ids+local.source_room_ids)).sorted();return a
    }
}
