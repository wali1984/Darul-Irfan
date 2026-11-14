import { shell } from "./layout.js";

export const POLICY_VERSION = "2026-11-06";
export const SUPPORT_EMAIL = "admin@naqshbandiaowaisiah.us";

const STYLE = `.policy{max-width:820px;padding:48px 0 80px}.policy h1{font-size:clamp(36px,6vw,60px);line-height:1.1;margin:12px 0 20px}.policy h2{font-size:30px;margin:32px 0 12px}.policy p,.policy li{color:var(--ink)}.policy a{text-decoration:underline;text-underline-offset:3px}.policy ul,.policy ol{padding-left:24px}.policy li{margin:10px 0}.policy .updated{color:var(--muted);font-size:14px}.policy .actions{display:flex;gap:12px;flex-wrap:wrap;margin:24px 0}.policy .actions a{text-decoration:none}`;

const privacy = `
  <h1>Privacy policy</h1>
  <p class="updated">Darul Irfan app and companion websites · Updated November 6, 2026</p>
  <p>This page explains the information used by Darul Irfan's reading, prayer, media and community features. For privacy questions or a data request, contact <a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a>.</p>
  <h2>Reading and prayer tools</h2>
  <p>Prayer calculations, bookmarks, personal prayer and Zikr records, reading progress and downloaded files are primarily stored on your device. Phone backup or device-transfer services may also retain local settings and records. Clearing app storage or uninstalling does not necessarily remove a phone backup.</p>
  <p>Loading content, audio, PDFs and transcripts sends the requested resource and normal connection information, such as IP address, to our service or its content provider. Public content is delivered through services including Cloudflare and GitHub. Embedded YouTube playback and links opened in other apps are also handled by those providers.</p>
  <h2>Location and optional online features</h2>
  <p>You can choose a city manually. Device location can be used for local prayer times and Qibla. The phone's geocoding service may receive a city search or coordinates to find a place name.</p>
  <p>Weather sends the selected location rounded to 0.1 degree to the Darul Irfan service and Apple WeatherKit. Nearby-masjid searches send the selected coordinates to our service and Google Places; a device-derived location can be more specific than the weather location. These requests can appear in service caches and operational logs. Weather and location permissions can be changed in the app or phone settings.</p>
  <h2>Adult community profiles and participation</h2>
  <p>Community profiles, membership and interactive participation are for adults aged 18 or older. Reading and available anonymous listening do not require a community profile. The website checks a date of birth locally before profile entry; that date is not sent to the server or saved. Adult declarations and the accepted community-terms version may be recorded with your community account.</p>
  <p>Depending on how you join, we store a name, city, country, optional contact email, sign-in provider identifier, invitation or visitor identity, membership, role and session credentials. Apple or Google sign-in can provide a name and email. Joining by invitation or as a visitor also creates a service identity; it is not necessarily anonymous.</p>
  <p>Named participation records include session identity and first/last presence times. Relevant Halqah admins and authorized Silsila Markaz officers can inspect and export profiles and attendance. Community membership and attendance can reveal religious participation. Other members may see the name or place attached to content you share.</p>
  <h2>Messages, meetings and recordings</h2>
  <p>Community features can process messages, Dua requests, reports, posts and uploaded photos, audio, video or files. Hiding your display name on a Dua request does not make the request anonymous to the service. Safety reports and their review notes are available to authorized reviewers.</p>
  <p>Live meetings use Cloudflare RealtimeKit for participant information, audio/video and supported chat or attachments, including private messages. Administrators may record meetings for the group's recordings. Use microphone and camera controls carefully and avoid sharing another person's private information without permission.</p>
  <p>Admin voice assistance uses the device's speech-recognition service. Depending on the platform, installed language and service, speech processing may use the recognition provider's servers. It is not an on-device-only feature.</p>
  <h2>Notifications and diagnostics</h2>
  <p>Enabled remote alerts use an installation identifier, an Apple push or Firebase/Google push token, language, timezone, app version and selected topics. Community notifications may link a device registration to an account. Turning alerts off requests removal of the relevant server registration; phone and delivery-provider data are managed separately.</p>
  <p>Opt-in iOS diagnostics can send app/OS information and diagnostic or performance payloads. The app does not include an advertising SDK or Firebase Analytics/Crashlytics. This does not mean third-party video, sign-in, operating-system and delivery services receive no connection or device information.</p>
  <h2>Who processes information</h2>
  <p>Information is processed to deliver the features you use, manage community access and attendance, respond to reports and operate the service. Depending on the feature, providers include Cloudflare, Apple, Google/Firebase, GitHub and media hosts. You can read <a href="https://www.cloudflare.com/privacypolicy/" target="_blank" rel="noopener">Cloudflare's policy</a>, <a href="https://www.apple.com/legal/privacy/" target="_blank" rel="noopener">Apple's policy</a> and <a href="https://policies.google.com/privacy" target="_blank" rel="noopener">Google's policy</a>. Opening a third-party website or app also brings that service's own practices into scope.</p>
  <h2>Storage, deletion and your choices</h2>
  <p>Accounts, profiles and participation data are stored on the service, rather than only on the phone. Published organizational content, recordings, operational logs, backups and provider-held records can have different retention from your sign-in account. Uninstalling the app does not request deletion of server data.</p>
  <p>You can request account and associated-data deletion in the app or through the <a href="/delete-account">account and data deletion page</a>. Contact support about a particular post, recording, provider-held record or data retained after an account is removed. We may need to verify the request before changing personal data. No universal completion or retention period is promised on this page.</p>
  <p>Parents or guardians may use the same contact address if a child has created a community profile or supplied personal information. Do not send passwords, sign-in codes or a child's identity document by email.</p>
  <h2>Updates</h2>
  <p>Changes to features or data handling will be reflected in this page. The date above identifies this version.</p>`;

const deletion = `
  <h1>Delete your account or data</h1>
  <p class="updated">Darul Irfan app and companion websites · Updated November 6, 2026</p>
  <p>You can request deletion without reinstalling the app or signing in to this website.</p>
  <div class="actions"><a class="btn btn-gold" href="mailto:${SUPPORT_EMAIL}?subject=Darul%20Irfan%20account%20or%20data%20deletion">Email a deletion request</a></div>
  <p>If an email app does not open, write to <a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a> with the subject “Darul Irfan account or data deletion”. Sending the email starts a request; opening this page or tapping the link does not delete anything.</p>
  <h2>What to include</h2>
  <ul><li>Say whether you want the whole account removed or particular data deleted.</li><li>Provide the account email, if you used one, or enough non-sensitive detail to find the profile, such as the display name and Halqah. Website visitors can say which website and approximate session date they used.</li><li>For a particular message, photo or recording, identify the item and group so it can be reviewed.</li></ul>
  <p>Do not send passwords, verification codes or identity documents. We may ask for a safe way to verify that the account or data belongs to you. Parents or guardians can request help with a child's profile or data.</p>
  <h2>From inside the app</h2>
  <p>Open the Halqah area, find your account controls and choose “Delete my account”. Read and confirm the deletion prompt. If this fails or you cannot access the account, use the email route above.</p>
  <h2>What deletion covers</h2>
  <p>Account deletion removes the service account and associated sign-in sessions, memberships and profile data. Associated attendance and personal community records are handled by the account-deletion process. Published group content, shared recordings, operational records, backups and records held by meeting or delivery providers may need separate review or provider removal.</p>
  <p>Ask for those items in the same request where relevant. Removing an account does not necessarily remove organizational content or copies other people have already received. Support can explain the result and any retained records for your request; this page does not promise a fixed completion time.</p>
  <p>Local downloads and personal reading or prayer records can be cleared using the app's storage controls. Phone backup and device-transfer copies are controlled separately in your device or cloud-backup settings.</p>
  <p><a href="/privacy">Read the privacy policy</a> for the information used by each feature.</p>`;

const terms = `
  <h1>Community terms</h1>
  <p class="updated">Version ${POLICY_VERSION} · Darul Irfan community features</p>
  <p>Community profiles and interactive participation are for adults aged 18 or older. Public reading and available listening without a profile remain separate from community membership.</p>
  <h2>Take care of the people here</h2>
  <ul><li>Do not harass, threaten, bully or abuse another person.</li><li>Do not share sexual content, hate speech, illegal content or material that promotes harm.</li><li>Do not spam, deceive people or impersonate another person or an administrator.</li><li>Do not publish another person's private information, photos, recordings or messages without their permission.</li><li>Use group posts, chats, Dua requests and meetings respectfully and for their intended purpose.</li></ul>
  <h2>Privacy and online safety</h2>
  <p>Avoid posting your home address, phone number, passwords or financial details. Other participants may retain content you share. Group administrators may record meetings. Read the <a href="/privacy">privacy policy</a> before creating a profile or sharing information.</p>
  <h2>Reports and moderation</h2>
  <p>Use an available report action or contact a Halqah admin about harmful content or behavior. You can also contact <a href="mailto:${SUPPORT_EMAIL}">${SUPPORT_EMAIL}</a>. Authorized reviewers consider reports and coordinate with the responsible admins. Appropriate actions can include removing content, restricting participation or removing membership. A report's review status does not itself hide content or block a person.</p>
  <p>Use available block or mute controls to manage interactions. If there is an immediate danger, contact the appropriate local emergency service rather than waiting for an app report.</p>
  <h2>Account and data requests</h2>
  <p>You can request removal of your account or associated information through the <a href="/delete-account">deletion page</a>. Participation requires acceptance of the current community terms.</p>`;

export function policyPage(kind, site, others, domain) {
  const titles = { privacy: "Privacy policy", "delete-account": "Account and data deletion", "community-terms": "Community terms" };
  const bodies = { privacy, "delete-account": deletion, "community-terms": terms };
  if (!bodies[kind]) return null;
  return shell({ site, others, title: `${titles[kind]} · Darul Irfan`, description: `${titles[kind]} for the Darul Irfan app and companion websites.`,
    active: "", extraStyle: STYLE, body: `<article class="wrap policy">${bodies[kind]}</article>` })
    .replace(/href="\/(#live|#halqahs|method-of-zikr|shajra)"/g, (_, path) => `href="https://oursheikh.${domain}/${path}"`);
}
