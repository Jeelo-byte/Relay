import Foundation
public enum DemoData {
    public static let maya=Party(id:"telegram:maya",name:"Maya Chen",network:.telegram)
    public static let alex=Party(id:"whatsapp:alex",name:"Alex Rivera",network:.whatsapp)
    public static let sam=Party(id:"discord:sam",name:"Sam Patel",network:.discord)
    public static let rooms=[ChatRoom(id:"!demo-tickets:relay.local",name:"Maya Chen",network:.telegram,optedIn:true),ChatRoom(id:"!demo-weekend:relay.local",name:"Weekend plans",network:.whatsapp,optedIn:true),ChatRoom(id:"!demo-studio:relay.local",name:"Studio crew",network:.discord,optedIn:true)]
    public static func date(_ days:Int)->String { Calendar.current.date(byAdding:.day,value:days,to:Date())!.formatted(.iso8601.year().month().day().dateSeparator(.dash)) }
    public static var messages:[ChatMessage] {
        let t=Clock.ms
        return [
            ChatMessage(room:rooms[0].id,event:"$demo-ticket",sender:maya,text:"Can you grab my ticket? I'll pay you back $40 by Friday.",ts:t-7200000,network:.telegram),
            ChatMessage(room:rooms[0].id,event:"$demo-yes",sender:.me,text:"Yeah ok, I'll grab yours too.",ts:t-7140000,network:.telegram),
            ChatMessage(room:rooms[1].id,event:"$demo-dinner",sender:alex,text:"I owe you $25 for dinner. I'll send it tomorrow.",ts:t-86400000,network:.whatsapp),
            ChatMessage(room:rooms[1].id,event:"$demo-thanks",sender:.me,text:"Sounds good, thank you!",ts:t-86340000,network:.whatsapp),
            ChatMessage(room:rooms[2].id,event:"$demo-design",sender:.me,text:"I'll send you the final poster on Sunday.",ts:t-3600000,network:.discord),
            ChatMessage(room:rooms[2].id,event:"$demo-deal",sender:sam,text:"Perfect, that works for me.",ts:t-3540000,network:.discord),
            ChatMessage(room:rooms[2].id,event:"$demo-book",sender:sam,text:"I'll return your design book yesterday before 5.",ts:t-172800000,network:.discord)
        ]
    }
    public static var agreements:[Agreement] {
        let m=messages
        var ticket=Agreement(title:"Concert tickets",parties:[.me,maya],obligations:[Obligation(from:maya.id,to:Party.me.id,what:"Pay back your concert ticket",amount:Money(minor:4000,currency:"USD",assumed:true,raw:"$40"),due:Due(date:date(6),raw:"Friday",ambiguous:true))],lifecycle:.agreed,kind:.payment)
        attach(&ticket,Array(m[0...1])); ticket.user_note="Sample agreement. Review each term before accepting."
        var dinner=Agreement(title:"Dinner, settled fairly",parties:[.me,alex],obligations:[Obligation(from:alex.id,to:Party.me.id,what:"Reimburse dinner",amount:Money(minor:2500,currency:"USD",raw:"$25"),due:Due(date:date(1),raw:"tomorrow"))],review:.accepted,lifecycle:.agreed,kind:.payment)
        attach(&dinner,Array(m[2...3]));dinner.timeline.append(TimelineEvent("accepted"))
        var poster=Agreement(title:"The final poster",parties:[.me,sam],obligations:[Obligation(from:Party.me.id,to:sam.id,what:"Send the final poster",due:Due(date:date(1),raw:"Sunday"))],review:.accepted,lifecycle:.agreed,kind:.task)
        attach(&poster,Array(m[4...5]));poster.timeline.append(TimelineEvent("accepted"))
        var book=Agreement(title:"Bring the design book back",parties:[.me,sam],obligations:[Obligation(from:sam.id,to:Party.me.id,what:"Return your design book",due:Due(date:date(-1),raw:"yesterday"))],review:.accepted,lifecycle:.agreed,kind:.item)
        attach(&book,[m[6]]);book.timeline.append(TimelineEvent("accepted"))
        return [ticket,book,dinner,poster]
    }
    private static func attach(_ a:inout Agreement,_ messages:[ChatMessage]) { a.evidence=messages.map { Evidence(message:$0,supports:["lifecycle","obligations[0].what","obligations[0].amount","obligations[0].due"]) }; a.covered_event_ids=messages.map(\.event_id);a.source_room_ids=Array(Set(messages.map(\.room_id))) }
}
