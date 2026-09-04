/** Shape of data/oxp-2026.json — one object per Odoo Experience edition. */

export type OxpTagCategory = {
  id: number;
  name: string;
};

export type OxpTag = {
  id: number;
  name: string;
  category_id: number | null;
  category: string | null;
  color: number | null;
};

export type OxpSpeaker = {
  id: number;
  name: string;
  function: string | null;
  company: string | null;
  biography_html: string | null;
  biography_text: string | null;
  image_url: string | null;
};

export type OxpTrackKind =
  | "talk"
  | "session"
  | "masterclass"
  | "keynote"
  | "opening"
  | "break"
  | "social"
  | "tba";

export type OxpTrack = {
  id: number;
  sequence: number;
  name: string;
  slug: string | null;
  url: string;
  kind: OxpTrackKind;
  day: string | null;
  weekday: string | null;
  time_label: string | null;
  start_time: string | null;
  end_time: string | null;
  starts_at: string | null;
  ends_at: string | null;
  timezone: string;
  duration_minutes: number | null;
  duration_label: string | null;
  location: string | null;
  speaker_line: string | null;
  tag_ids: number[];
  tags: OxpTag[];
  speaker_ids: number[];
  speakers: OxpSpeaker[];
  description_html: string | null;
  description_text: string | null;
  image_url: string | null;
  coming_soon: boolean;
};

export type OxpExhibitor = {
  id: number;
  sequence: number;
  name: string;
  slogan: string | null;
  level: string;
  country: string | null;
  logo_url: string | null;
  url: string | null;
  website: string | null;
  email: string | null;
  phone: string | null;
  hours: string | null;
  contact_name: string | null;
};

export type OxpEvent = {
  id: number;
  code: string;
  short_name: string;
  name: string;
  slug: string;
  timezone: string;
  venue_name: string;
  venue_address: string;
  country_code: string;
  has_map: boolean;
  website_url: string;
  agenda_url: string;
  tracks_url: string;
  exhibitors_url: string;
  starts_on: string | null;
  ends_on: string | null;
  scraped_at: string;
};

export type OxpEventSeed = {
  event: OxpEvent;
  stats: {
    tracks: number;
    tracks_with_description: number;
    speakers: number;
    tags: number;
    locations: number;
    exhibitors: number;
    days: string[];
  };
  tag_categories: OxpTagCategory[];
  tags: OxpTag[];
  locations: string[];
  speakers: OxpSpeaker[];
  tracks: OxpTrack[];
  exhibitors: OxpExhibitor[];
};

/** Full seed: editions stay separate (talks are never merged). */
export type OxpSeed = {
  default_event_id: number;
  scraped_at: string;
  events: OxpEventSeed[];
};
