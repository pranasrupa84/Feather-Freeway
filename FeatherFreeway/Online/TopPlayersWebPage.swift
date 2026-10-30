import SwiftUI
import WebKit

struct TopPlayersWebPage: UIViewRepresentable {
    let online: PlayerOnlineStore
    let close: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(online: online, close: close) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "leaderboard")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.navigationDelegate = context.coordinator
        context.coordinator.web = web
        web.loadHTMLString(Self.page, baseURL: nil)
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.payload = payload
        context.coordinator.render()
    }
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        web.configuration.userContentController.removeScriptMessageHandler(forName: "leaderboard")
        web.navigationDelegate = nil
    }
    private var payload: [String: Any] {
        ["name": online.playerName, "loading": online.isLoading,
         "message": [online.leaderboardMessage, online.syncMessage].compactMap { $0 }.joined(separator: " · "),
         "players": online.players.map { ["name": $0.name, "score": $0.best_score, "avatar": $0.avatar ?? "clover"] as [String: Any] }]
    }
    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let online: PlayerOnlineStore
        let close: () -> Void
        weak var web: WKWebView?
        var ready = false
        var payload: [String: Any] = [:]
        init(online: PlayerOnlineStore, close: @escaping () -> Void) { self.online = online; self.close = close }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; render() }
        func render() {
            guard ready, let data = try? JSONSerialization.data(withJSONObject: payload), let json = String(data: data, encoding: .utf8) else { return }
            web?.evaluateJavaScript("window.renderLeaderboard(\(json))", completionHandler: nil)
        }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: String] else { return }
            switch body["action"] {
            case "close": close()
            case "refresh": Task { await online.refreshLeaderboard() }
            case "save":
                let name = (body["name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { online.playerName = String(name.prefix(32)) }
            default: break
            }
        }
    }
    private static let page = #"""
    <!doctype html><html lang="en"><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"><meta charset="utf-8">
    <style>
    *{box-sizing:border-box}body{margin:0;background:#68a533;color:#192b42;font:700 16px -apple-system,BlinkMacSystemFont,sans-serif}main{max-width:700px;margin:auto;padding:24px 18px 40px}button,input{font:inherit;color:inherit}button{cursor:pointer;border:3px solid #192b42;border-radius:14px;background:#f4c329;box-shadow:0 4px #192b42;padding:12px 16px;min-height:48px}header{display:flex;align-items:center;justify-content:space-between;gap:16px}h1{font-size:32px;letter-spacing:1px;margin:0}.sign{margin:28px 0 20px;text-align:center;background:#007f55;border:5px solid #192b42;border-radius:24px;padding:22px 12px;box-shadow:inset 0 0 0 4px #f8efd6,0 6px #192b42;color:#f6c328}.sign p{color:#fff;margin:10px 0 0;font-size:14px}.profile{background:#f3e9ce;border:3px solid #192b42;border-radius:18px;padding:16px;margin-bottom:22px}.profile label{display:block;font-size:12px;letter-spacing:1px;margin-bottom:10px}.form{display:flex;gap:10px}input{width:100%;min-width:0;border:2px solid #192b42;border-radius:10px;padding:12px;background:#fffaf0}#status{text-align:center;line-height:1.5}ol{padding:0;list-style:none;display:grid;gap:12px}li{display:flex;align-items:center;gap:12px;background:#f3e9ce;border:3px solid #192b42;border-radius:16px;padding:14px;box-shadow:0 4px #192b42}li:first-child{background:#f7d966}.rank{font-size:22px;min-width:28px}.hen{font-size:30px}.name{overflow-wrap:anywhere;flex:1}.score{text-align:right;font-size:22px}.score small{display:block;font-size:10px;letter-spacing:1px}footer{text-align:center;font-size:12px;margin-top:24px}@media(max-width:360px){h1{font-size:26px}.form{flex-wrap:wrap}.score{font-size:18px}}
    </style></head><body><main><header><button onclick="send('close')" aria-label="Back">←</button><strong>FEATHER FREEWAY</strong><button onclick="send('refresh')" aria-label="Refresh">↻</button></header><section class="sign"><h1>TOP PLAYERS</h1><p>THE FASTEST FEATHERS ON THE FREEWAY</p></section><section class="profile"><label for="driver">YOUR DRIVER NAME</label><form class="form" onsubmit="event.preventDefault();send('save',document.querySelector('#driver').value)"><input id="driver" maxlength="32" autocomplete="nickname"><button>Save</button></form></section><p id="status" role="status" aria-live="polite">Loading drivers…</p><ol id="players"></ol><footer>FINISH A TRIP. SET YOUR RECORD. CLIMB THE BOARD.</footer></main><script>
    function send(action,name=''){window.webkit.messageHandlers.leaderboard.postMessage({action,name})}
    window.renderLeaderboard=function(data){const input=document.querySelector('#driver');if(document.activeElement!==input)input.value=data.name||'';const rows=data.players||[];document.querySelector('#status').textContent=data.message||(data.loading?'Loading drivers…':rows.length?'BEST RUNS · LIVE STANDINGS':'No players yet. Finish a trip to join the leaderboard.');const list=document.querySelector('#players');list.replaceChildren();rows.forEach((player,index)=>{const row=document.createElement('li');const rank=document.createElement('span');rank.className='rank';rank.textContent=index+1;const hen=document.createElement('span');hen.className='hen';hen.textContent='🐔';const name=document.createElement('span');name.className='name';name.textContent=player.name;const score=document.createElement('span');score.className='score';score.textContent=Number(player.score).toLocaleString();const label=document.createElement('small');label.textContent='BEST SCORE';score.append(label);row.append(rank,hen,name,score);list.append(row)})};
    </script></body></html>
    """#
}
