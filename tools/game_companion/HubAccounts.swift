import SwiftUI
import AppKit
import UniformTypeIdentifiers

// The Accounts page, its connect forms, the sales block and the catalog and alerts cards.
// Split out of Hub.swift on 2026-10-24 with no change in behaviour, so pages can have one owner each.
extension CompanionInterfaceView {
 var hubAccounts: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:12) {
    Text("Logins are saved privately on this Mac. You paste them into the app yourself, never into chat.").font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.55)).padding(.bottom,4)
    hubAccountRow("google","waveform",Noir.crimson,"Google Gemini","Friday's voice and eyes.",live.hasKey ? "Connected" : "Not connected",live.hasKey ? HubColor.green : Noir.crimsonLight,live.hasKey ? "Manage" : "Connect") { hubGoogleForm }
    hubAccountRow("twitch","scissors",HubColor.violet,"Twitch","Makes clips when you ask and runs the Stream page.",clips.signedIn ? "Connected" : "Not connected",clips.signedIn ? HubColor.green : Noir.crimsonLight,clips.signedIn ? "Manage" : "Connect") { clipSettings }
    hubAccountRow("stocks","chart.line.uptrend.xyaxis",HubColor.green,"Stock bot snapshot","Reads the public practice snapshot. No login needed.","Read-only",HubColor.green,nil) { EmptyView() }
    hubAccountRow("moomoo","lock.shield.fill",HubColor.slate,"Moomoo (real money)","Not connected here, on purpose. Real money only runs on your Mac with your three switches.","Walled off",HubColor.slate,nil) { EmptyView() }
    hubAccountRow("counters","chart.bar.fill",HubColor.amber,"GoatCounter (store visits)","Reads your site's public visitor counters. No login needed.","Read-only",HubColor.green,nil) { EmptyView() }
    hubAccountRow("feed","megaphone.fill",HubColor.violet,"Your ECS feed","Reads the feed files findhotstuff.com already publishes. No login needed.","Read-only",HubColor.green,nil) { EmptyView() }
    hubAccountRow("github","gearshape.2.fill",HubColor.coral,"GitHub (automation status)","Reads the public status of your automations. No login needed.","Read-only",HubColor.green,nil) { EmptyView() }
    hubAccountRow("stripe","bag.fill",HubColor.amber,"Stripe (sales)","Orders and revenue, from a read-only key you paste yourself. It can't move money.",sales.hasKey ? "Connected" : "Not connected",sales.hasKey ? HubColor.green : Noir.crimsonLight,sales.hasKey ? "Manage" : "Connect") { hubStripeForm }
    hubAccountRow("room","person.3.fill",HubColor.violet,"GitHub (Meeting Room posting)","Lets you post to the shared thread from this app. A key limited to Issues on one repo.",meeting.hasToken ? "Connected" : "Not connected",meeting.hasToken ? HubColor.green : Noir.crimsonLight,meeting.hasToken ? "Manage" : "Connect") { hubRoomTokenForm }
    hubAccountRow("cj","shippingbox.fill",HubColor.coral,"CJ Dropshipping (supplier)","Reads how fresh your product list is from the public site. The supplier login itself stays in GitHub.",hubCatalogStatus.0,hubCatalogStatus.1,nil) { EmptyView() }
    hubAccountRow("socials","person.2.fill",HubColor.violet,"X, TikTok, Facebook","Not connected. She would prepare posts and you click Post. TikTok and Meta also need their own app reviews first.","Coming later",HubColor.slate,nil) { EmptyView() }
   }
   .padding(.horizontal,32).padding(.bottom,30)
  }
  .scrollIndicators(.hidden)
 }

 // Connect forms open right inside the row, so there is nothing to hunt for.
 func hubAccountRow<Form: View>(_ key: String,_ icon: String,_ tint: Color,_ name: String,_ detail: String,_ status: String,_ statusTint: Color,_ button: String?,@ViewBuilder form: () -> Form) -> some View {
  let open = hub.expanded == key
  let formView = form()
  return VStack(alignment:.leading,spacing:14) {
   HStack(spacing:16) {
    ZStack {
     RoundedRectangle(cornerRadius:14,style:.continuous).fill(LinearGradient(colors:[tint,tint.opacity(0.55)],startPoint:.topLeading,endPoint:.bottomTrailing)).frame(width:46,height:46)
     Image(systemName:icon).font(.system(size:19,weight:.semibold)).foregroundStyle(Color.white)
    }
    VStack(alignment:.leading,spacing:3) {
     Text(name).font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
     Text(detail).font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(2)
    }
    Spacer()
    hubPill(status.uppercased(),tint:statusTint)
    if let button = button {
     Button(open ? "Done" : button) { withAnimation(.spring(response:0.45,dampingFraction:0.86)) { hub.expanded = open ? "" : key } }
      .buttonStyle(PillButtonStyle(tint:open ? Color.white.opacity(0.12) : Noir.crimson))
    }
   }
   if open {
    Divider().overlay(Color.white.opacity(0.10))
    formView
   }
  }
  .padding(16)
  .hubCard()
 }

 // Alerts the automations raised on GitHub. A green run can still be doing nothing useful (X refusing posts), so these show here.
 @ViewBuilder var hubIssuesCard: some View {
  if let open = ventures.issues, !open.isEmpty {
   VStack(alignment:.leading,spacing:12) {
    Text("Alerts your automations raised").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
    ForEach(open) { issue in
     HStack(spacing:12) {
      Image(systemName:"exclamationmark.circle.fill").font(.system(size:18)).foregroundStyle(HubColor.amber)
      VStack(alignment:.leading,spacing:2) {
       Text(issue.title).font(.system(size:13.5,weight:.medium,design:.rounded)).foregroundStyle(Color.white.opacity(0.9)).lineLimit(2)
       Text("Raised \(hubAgo(issue.since)). Open until it's fixed or closed on GitHub.").font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.5))
      }
      Spacer()
      if let url = URL(string:issue.url), !issue.url.isEmpty {
       Button("Open") { NSWorkspace.shared.open(url) }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
      }
     }
    }
   }
   .padding(16)
   .frame(maxWidth:.infinity,alignment:.leading)
   .hubCard()
  }
 }

 var hubCatalogStatus: (String,Color) {
  guard let cat = ventures.catalog else { return ("Loading",HubColor.slate) }
  return cat.isStale() ? ("Stale",Noir.crimsonLight) : ("Read-only",HubColor.green)
 }

 // The product list's age. This is the check that would have caught the month the CJ refresh was stuck.
 @ViewBuilder var hubCatalogCard: some View {
  if let cat = ventures.catalog {
   let stale = cat.isStale()
   HStack(spacing:14) {
    Image(systemName:stale ? "exclamationmark.triangle.fill" : "shippingbox.fill").font(.system(size:22)).foregroundStyle(stale ? HubColor.amber : HubColor.green)
    VStack(alignment:.leading,spacing:2) {
     Text("Product list: \(cat.count) products in \(cat.categories) categories").font(.system(size:14.5,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
     Text(cat.refreshed == nil ? "Couldn't read the date of the last refresh." : "Last refreshed \(hubAgo(cat.refreshed)). The refresh is meant to run every 3 days.\(stale ? " It is overdue. Last time, CJ had switched the API access off, and logging in to CJ and reactivating it fixed it." : "")")
      .font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.6))
    }
    Spacer()
    if stale, let url = URL(string:"https://github.com/matthewferreira818/hotstuff/actions/workflows/refresh-products.yml") {
     Button("Open") { NSWorkspace.shared.open(url) }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
    }
   }
   .padding(14)
   .hubCard()
  }
 }

 func hubCurrency(_ value: Double,_ code: String) -> String { value.formatted(.currency(code:code.uppercased())) }
 func hubRevenue(_ period: StripePeriod) -> String {
  if period.revenue.isEmpty { return "no sales yet" }
  return period.revenue.sorted { $0.key < $1.key }.map { hubCurrency($0.value,$0.key) }.joined(separator:" + ")
 }

 // Orders and revenue from Stripe, or a prompt to connect it.
 @ViewBuilder var hubSalesBlock: some View {
  if sales.hasKey {
   if let s = sales.sales {
    HStack(spacing:10) {
     hubPill(s.testMode ? "STRIPE · TEST MODE" : "STRIPE · READ-ONLY",tint:s.testMode ? HubColor.amber : HubColor.green)
     if sales.loading { ProgressView().controlSize(.small) }
     Spacer()
     Button { Task { await sales.refresh(force:true) } } label: { Label("Refresh sales",systemImage:"arrow.clockwise") }
      .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12))).disabled(sales.loading)
    }
    LazyVGrid(columns:[GridItem(.adaptive(minimum:200),spacing:14)],spacing:14) {
     hubStat("Orders today",String(s.today.orders),hubRevenue(s.today),tint:Color.white)
     hubStat("Orders, 7 days",String(s.week.orders),hubRevenue(s.week),tint:Color.white)
     hubStat("Orders, 30 days",String(s.month.orders),hubRevenue(s.month) + (s.capped ? " · first 500 only" : ""),tint:s.month.orders > 0 ? HubColor.green : Color.white)
    }
    if !s.latest.isEmpty {
     VStack(alignment:.leading,spacing:10) {
      Text("Latest orders").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
      ForEach(s.latest) { order in
       HStack {
        Text(hubCurrency(order.amount,order.currency)).font(.system(size:13.5,weight:.semibold,design:.rounded)).foregroundStyle(Color.white.opacity(0.9))
        Spacer()
        Text(hubAgo(order.time)).font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.5))
       }
      }
     }
     .padding(18).frame(maxWidth:.infinity,alignment:.leading).hubCard()
    }
    if !sales.message.isEmpty {
     Text("Couldn't refresh sales just now: \(sales.message)").font(.system(size:12,design:.rounded)).foregroundStyle(HubColor.amber)
    }
   } else if !sales.message.isEmpty {
    VStack(alignment:.leading,spacing:10) {
     Text("Sales didn't load").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
     Text(sales.message).font(.system(size:13,design:.rounded)).foregroundStyle(Color.white.opacity(0.65))
     Button("Open the Stripe settings") { hub.expanded = "stripe"; hubSelect(.accounts) }.buttonStyle(PillButtonStyle())
    }
    .padding(18).frame(maxWidth:.infinity,alignment:.leading).hubCard()
   } else {
    ProgressView().controlSize(.regular).frame(maxWidth:.infinity).padding(20)
   }
  } else {
   HStack(spacing:14) {
    Image(systemName:"bag.fill").font(.system(size:22)).foregroundStyle(HubColor.amber)
    VStack(alignment:.leading,spacing:2) {
     Text("See orders and revenue here").font(.system(size:14.5,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
     Text("Connect Stripe with a read-only key. It takes about two minutes.").font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.6))
    }
    Spacer()
    Button("Connect Stripe") { hub.expanded = "stripe"; hubSelect(.accounts) }.buttonStyle(PillButtonStyle())
   }
   .padding(14)
   .hubCard()
  }
 }

 // The Stripe key: a restricted, read-only key. A full secret key is refused on purpose.
 @ViewBuilder var hubStripeForm: some View {
  if sales.hasKey {
   HStack(spacing:10) {
    Label("Read-only key saved privately on this Mac",systemImage:"checkmark.seal.fill").font(.system(size:13,weight:.medium,design:.rounded)).foregroundStyle(HubColor.green)
    Spacer()
    Button("Refresh now") { Task { await sales.refresh(force:true) } }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12))).disabled(sales.loading)
    Button("Remove key") { sales.forget() }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
   }
   if !sales.message.isEmpty { Text(sales.message).font(.system(size:12.5,design:.rounded)).foregroundStyle(HubColor.amber) }
  } else {
   Text("1. Click Open Stripe keys and sign in.\n2. Press Create restricted key and name it Game Companion.\n3. Set Charges to Read. Leave everything else on None.\n4. Create it, copy the key (it starts with rk_live_), paste it below and press Save key. Never paste it into a chat.\nIf Stripe's screens look different, tell me what you see and I'll adjust these steps.").font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.65))
   HStack(spacing:10) {
    Button("Open Stripe keys") { NSWorkspace.shared.open(URL(string:"https://dashboard.stripe.com/apikeys")!) }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
    SecureField("Paste your key here",text:$sales.keyInput).noirField()
    Button("Save key") { sales.save() }.buttonStyle(PillButtonStyle())
   }
   if !sales.message.isEmpty { Text(sales.message).font(.system(size:12.5,design:.rounded)).foregroundStyle(HubColor.amber) }
  }
 }

 // The Google key: get one free (no card needed), paste it, and it is saved privately on this Mac.
 @ViewBuilder var hubGoogleForm: some View {
  if live.hasKey {
   HStack {
    Label("Key saved privately on this Mac",systemImage:"checkmark.seal.fill").font(.system(size:13,weight:.medium,design:.rounded)).foregroundStyle(HubColor.green)
    Spacer()
    Button("Remove key") { live.forgetKey() }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
   }
  } else {
   Text("1. Click Get a free key and sign in with Google. No card needed.\n2. Create an API key and copy it.\n3. Paste it below and press Save key. Never paste it into a chat.").font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.65))
   HStack(spacing:10) {
    Button("Get a free key") { NSWorkspace.shared.open(URL(string:"https://aistudio.google.com/apikey")!) }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
    SecureField("Paste your key here",text:$live.keyInput).noirField()
    Button("Save key") { live.saveKey() }.buttonStyle(PillButtonStyle())
   }
  }
 }

 func hubSoon(_ section: HubSection,_ title: String,_ blurb: String,_ bullets: [String]) -> some View {
  VStack(spacing:18) {
   Spacer(minLength:0)
   ZStack {
    RoundedRectangle(cornerRadius:26,style:.continuous).fill(LinearGradient(colors:[section.tint,section.tint.opacity(0.5)],startPoint:.topLeading,endPoint:.bottomTrailing)).frame(width:84,height:84)
    Image(systemName:section.icon).font(.system(size:34,weight:.semibold)).foregroundStyle(Color.white)
   }
   Text(title).font(.system(size:24,weight:.bold,design:.rounded)).foregroundStyle(Color.white)
   Text(blurb).font(.system(size:14,design:.rounded)).foregroundStyle(Color.white.opacity(0.65)).multilineTextAlignment(.center)
   hubPill("COMING NEXT",tint:section.tint)
   VStack(alignment:.leading,spacing:8) {
    ForEach(Array(bullets.enumerated()),id:\.offset) { _,line in
     HStack(alignment:.top,spacing:8) {
      Image(systemName:"circle.fill").font(.system(size:5)).foregroundStyle(section.tint).padding(.top,6)
      Text(line).font(.system(size:13,design:.rounded)).foregroundStyle(Color.white.opacity(0.7))
     }
    }
   }
   .padding(20).frame(maxWidth:440,alignment:.leading).hubCard()
   Spacer(minLength:0)
  }
  .frame(maxWidth:.infinity)
 }
}
