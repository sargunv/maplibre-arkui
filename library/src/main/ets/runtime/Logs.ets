/**
 * How severe a log record is.
 *
 * Values may be added in later releases; give a `switch` over it a `default`
 * branch.
 */
export enum MapLogLevel {
  /** Progress that needs no action. */
  INFO,
  /** Something unexpected that MapLibre recovered from. */
  WARN,
  /** A failure. */
  ERROR,
}

/** One message of the log. Fields may be added in later releases. */
export interface MapLogRecord {
  /** How severe the message is. */
  readonly level: MapLogLevel;
  /** The message text. */
  readonly message: string;
  /**
   * MapLibre Native's category for the message, such as `'database'` or
   * `'httpRequest'`, or undefined for the library's own messages. Values may
   * be added in later releases.
   */
  readonly category: string | undefined;
}

/** Receives each log record. */
export type MapLogHandler = (record: MapLogRecord) => void;
