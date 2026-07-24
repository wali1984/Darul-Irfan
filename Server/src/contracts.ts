export const schemaVersion = 1;

export type FeedSource = "youtube" | "facebook" | "website" | "announcement" | "event";
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
}
