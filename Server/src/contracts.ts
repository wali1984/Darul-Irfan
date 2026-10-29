export const schemaVersion = 1;

export type FeedSource = "youtube" | "facebook" | "website" | "announcement" | "event" | "whatsapp";
export type FeedKind = "post" | "video" | "announcement" | "event";
export type LiveState = "offline" | "scheduled" | "live" | "ended";
export type PushTopic = "liveZikr" | "broadcasts" | "announcements" | "events";

export interface OfficialFeedItem {
  id: string;
  source: FeedSource;
  kind: FeedKind;
  title: string;
  body?: string;
  sourceURL: string;
  imageURL?: string;
  videoID?: string;
  publishedAt: string;
  isFeatured: boolean;
}

export interface LiveSource {
  kind: "youtube" | "paltalk" | "ownedStream";
  url: string;
  videoID?: string;
  supportsBackgroundAudio: boolean;
}

export interface LiveBroadcast {
  id: string;
  state: LiveState;
  title: string;
  details?: string;
  scheduledStart?: string;
  startedAt?: string;
  endedAt?: string;
  sources: LiveSource[];
  updatedAt: string;
  /** False until the automatic broadcast (listeners + hub) is connected. */
  automaticBroadcast?: boolean;
  /** The host's last cue in the room this session ("L-3", "M-Nabvee"). */
  cue?: LiveCue;
  /** The Paltalk room while it is open: how many are in it, since when. */
  room?: { platform: "paltalk"; listeners: number; since?: string; url?: string };
}

/** The Silsila's Paltalk room, as Paltalk's public directory lists it. */
export interface PaltalkRoomStatus {
  online: boolean;
  listeners: number;
  since?: string;
  checkedAt: string;
}

export interface LiveCue {
  text: string;
  sender?: string;
  at: string;
}

export interface RemoteZikrSchedule {
  id: string;
  title: string;
  weekdays: number[];
  startHour: number;
  startMinute: number;
  durationMinutes: number;
  timeZoneIdentifier: string;
  joinURL?: string;
  instructions?: string;
  availabilityNote?: string;
}

export interface AppBootstrap {
  schemaVersion: number;
  generatedAt: string;
  minimumSupportedVersion: string;
  featureFlags: Record<string, boolean>;
  officialLinks: Record<string, string>;
  schedules: RemoteZikrSchedule[];
  live: LiveBroadcast;
  contentVersions: Record<string, number>;
}

export interface DeviceRegistration {
  installationID: string;
  apnsToken: string;
  locale: string;
  timeZone: string;
  topics: PushTopic[];
  environment: "sandbox" | "production";
  appVersion: string;
  /** Registers the phone for its member's Halqah notices only: an existing
   *  registration keeps the official topics it has. */
  keepTopics?: boolean;
}

export interface Env {
  DB: D1Database;
  ENVIRONMENT: string;
  PUBLIC_BASE_URL: string;
  YOUTUBE_CHANNEL_ID: string;
  FACEBOOK_PAGE_ID: string;
  FACEBOOK_GRAPH_VERSION: string;
  APNS_TOPIC: string;
  YOUTUBE_API_KEY?: string;
  FACEBOOK_PAGE_ACCESS_TOKEN?: string;
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  APNS_PRIVATE_KEY?: string;
  ADMIN_EDITOR_EMAILS?: string;
  ADMIN_BROADCASTER_EMAILS?: string;
  ACCESS_TEAM_DOMAIN?: string;
  ACCESS_AUD?: string;
  WHATSAPP_VERIFY_TOKEN?: string;
  WHATSAPP_APP_SECRET?: string;
  WHATSAPP_ALLOWED_SENDERS?: string;
  WHATSAPP_CHANNEL_URL?: string;
  /** Audience of an Apple identity token: the app's bundle id. Falls back to
   *  APNS_TOPIC, which is the same value. */
  APPLE_CLIENT_ID?: string;
  /** Pictures forwarded to the WhatsApp Business number. */
  MEDIA?: R2Bucket;
  /** Graph API token of the WhatsApp Business account, to fetch pictures. */
  WHATSAPP_ACCESS_TOKEN?: string;
  /** Signs the expiring links members open pictures with. */
  MEDIA_URL_SECRET?: string;
  /** Staff emails with every admin role (editor and broadcaster). */
  SUPER_ADMIN_EMAILS?: string;
  /** Cloudflare RealtimeKit, for in-app meetings and joined zikr. */
  REALTIME_ACCOUNT_ID?: string;
  REALTIME_APP_ID?: string;
  REALTIME_API_TOKEN?: string;
  REALTIME_PRESET_HOST?: string;
  REALTIME_PRESET_MEMBER?: string;
  /** Live zikr pipeline: the listeners' shared bearer token. */
  LISTENER_TOKEN?: string;
  /** The Paltalk room watched in Paltalk's directory, and its group number. */
  PALTALK_ROOM?: string;
  PALTALK_GROUP_ID?: string;
  /** Paltalk usernames whose room chat messages are cues (comma list). */
  LIVE_CUE_HOSTS?: string;
  /** Cloudflare Stream live input ids, in failover order ("A,B"). */
  STREAM_INPUTS?: string;
  /** Stream playback host, customer-<code>.cloudflarestream.com. */
  STREAM_CUSTOMER_HOST?: string;
  /** Secret Cloudflare sends with live input notifications. */
  STREAM_WEBHOOK_SECRET?: string;
  /** WhatsApp numbers told when part of the live pipeline fails. */
  ALERT_WHATSAPP_NUMBERS?: string;
  /** The WhatsApp Business number's id, to send those alerts from. */
  WHATSAPP_PHONE_NUMBER_ID?: string;
  /** Approved template (one body parameter) for alerts outside 24 hours. */
  ALERT_WHATSAPP_TEMPLATE?: string;
}

/** A private regional group as its members see it. The catalogue of groups is
 *  itself private, so a member is only ever told about their own. */
export interface MemberGroup {
  id: string;
  name: string;
  description?: string;
  meetingURL?: string;
  meetingNote?: string;
}

export type MemberGroupPostKind = "announcement" | "zikr";

export interface MemberGroupPost {
  id: string;
  kind: MemberGroupPostKind;
  title: string;
  body?: string;
  youtubeVideoID?: string;
  linkURL?: string;
  publishedAt: string;
}
