# Shared timer links on Eco

The Mac app shares timers as links to the Eco web timer, for example:

```
https://unreasonable.eco/timer?time=1200&text=Please%20wrap%20up.&lead=Keynote&people=40&accent=6926E3&timersize=150&name=Keynote
```

The web page already runs these: it reads `time`, `text`, `lead`, `done`, `over`, `people` and
`theme`, and ignores the Mac-only params (`accent`, `sound`, `chime15`, the `…size` params and
`name`). Two changes on Eco make them open in the Mac app where it's installed.

## 1. Associate the domain with the app

macOS opens an https link in an app (a universal link) only when the domain serves this file. It
must be served over HTTPS at exactly this path, with status 200 and no redirect.

```ruby
# config/routes.rb
get "/.well-known/apple-app-site-association", to: "static#apple_app_site_association", format: false
```

```ruby
# app/controllers/static_controller.rb
# Lets shared timer links (/timer?time=…) open in the Unreasonable Timer Mac app where it's
# installed; the form (edit=1) always stays on the web. Public, and touches no user data.
def apple_app_site_association
  render json: {
    applinks: {
      details: [{
        appIDs: ["B79A4CAS56.com.unreasonablegroup.timer"],
        components: [
          {"/": "/timer", "?": {edit: "*"}, exclude: true, comment: "The timer form stays on the web"},
          {"/": "/timer", "?": {time: "?*"}, comment: "Timers open in the Mac app where it's installed"}
        ]
      }]
    }
  }
end
```

If `StaticController` requires a signed-in user or verifies Pundit authorization after each
action, skip those for this action, as `timer` presumably does.

Links followed within unreasonable.eco (the form's Start button, the history list) stay on the
web: universal links only apply when the link comes from somewhere else.

Check it once deployed:

```sh
curl -sI https://unreasonable.eco/.well-known/apple-app-site-association   # 200, application/json
curl -s https://app-site-association.cdn-apple.com/a/v1/unreasonable.eco    # Apple's cached copy
```

Apple's CDN can take up to a day to pick up a new or changed file.

## 2. "Open in Mac app" on the web timer

Chrome and other non-Safari browsers never hand a link to an app, so give Mac visitors a way
across. In `app/views/static/timer.html.erb`, add to the countdown's hint, after the Edit link:

```erb
<span data-timer-open-app hidden> · <a href="untimer://open">Open in Mac app</a></span>
```

and in its script, next to the other `root.querySelector` lines:

```js
var openApp = root.querySelector('[data-timer-open-app]');
// The app takes the same params on its own untimer:// scheme.
if (openApp && /Mac/.test(navigator.platform)) {
  openApp.querySelector('a').href = 'untimer://open' + window.location.search;
  openApp.hidden = false;
}
```

and let the link through the click-to-start handler:

```js
if (event.target.closest('[data-timer-edit], [data-timer-open-app]')) { return; }
```

The browser asks once before opening the app. Without the app installed, Safari shows an
error and Chrome does nothing, which is why it is a link and not an automatic redirect.

## Optional: the shared name

Shared saved timers carry `name`. The page title could lead with it:

```erb
<% title [params[:name].to_s.squish.first(80).presence, timer_label, "Timer"].compact.join(" ") %>
```
