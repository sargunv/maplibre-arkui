/**
 * How severe a log record is.
 *
 * Values may be added in later releases; give a `switch` over it a `default`
 * branch.
 */
export enum MapLogLevel {
  /** Progress that needs no action. */
  INFO,
  /** Something unexpected that MapLibre worked around. */
  WARN,
  /** A failure. */
  ERROR,
}

/** One message of the log, which the library creates; fields may be added in later releases. */
export interface MapLogRecord {
  /** How severe the message is. */
  level: MapLogLevel;
  /** The message, without the library's `MapLibre:` hilog prefix. */
  message: string;
  /**
   * MapLibre Native's category for the message, such as `'database'` or
   * `'httpRequest'`, or undefined for the library's own messages. Values may
   * be added in later releases.
   */
  category: string | undefined;
}

/** Takes each record of the log; see `MapRuntime.setLogHandler()`. */
export type MapLogHandler = (record: MapLogRecord) => void;
