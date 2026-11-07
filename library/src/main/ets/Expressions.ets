// Style expressions: functions that build the JSON of MapLibre style-spec
// expressions, https://maplibre.org/maplibre-style-spec/expressions/.
//
// Each function is named after its operator in camelCase, such as `featureState`
// for `feature-state`. Symbols get words (`eq` for `==`, `add` for `+`), and
// `case`, a reserved word, is `cases`. Expressions are untyped: MapLibre checks
// an expression's types when it parses it, and a phantom `Expression<T>` would
// check nothing in ArkTS without a brand, or type assertions at every feature
// property with one.

import { FONT_SCALE_STATE } from './fontScale';

/** A JSON value, as a style holds it. */
export type JsonValue = string | number | boolean | null | JsonValue[] | JsonObject;

/** A JSON object. */
export interface JsonObject extends Record<string, JsonValue> {}

/**
 * An argument to an expression function: another expression, or a plain
 * number, string, boolean, or null, which the style reads as itself. A string
 * stands for a color where the expression expects one, as CSS writes it:
 * `'#ff0000'`, `'rgba(255, 0, 0, 0.5)'`, or `'#ff000080'`, whose alpha comes
 * last, unlike ArkUI's `'#80ff0000'`. An array isn't an argument; wrap it in
 * `literal()`.
 */
export type ExpressionInput = Expression | string | number | boolean | null;

/**
 * A style expression, which the map evaluates for each feature or zoom level.
 *
 * Build one with the functions of this module, such as `get()`,
 * `interpolate()`, and `match()`. For an operator that they don't
 * cover, use `call()`, or construct an expression from its style-spec
 * JSON. Use it in a `StyleLayer`'s `filter`, `paint`, and `layout`, and as
 * the `filter` of a feature query.
 *
 * MapLibre checks the expression's types when the map applies it, not this
 * library: an invalid expression in the content goes to
 * `MaplibreMap.onError`. An expression is immutable.
 */
export class Expression {
  private readonly json: JsonValue;
  private readonly key: string;

  /**
   * Creates an expression from its style-spec JSON, such as
   * `new Expression(['get', 'name'])`. The expression keeps a copy, so later
   * changes to `json` don't change it.
   */
  constructor(json: JsonValue) {
    this.key = JSON.stringify(json);
    this.json = JSON.parse(this.key) as JsonValue;
  }

  /** The style-spec JSON, which `JSON.stringify` writes for the expression. */
  toJSON(): JsonValue {
    return this.json;
  }

  /** The style-spec JSON as text, which two expressions share only when their JSON is the same. */
  toString(): string {
    return this.key;
  }
}

function jsonOf(input: ExpressionInput): JsonValue {
  return input instanceof Expression ? input.toJSON() : input;
}

/**
 * Calls the style-spec operator `operator` with `args`. For an operator that
 * this module has no function for, such as
 * `call('in', get('class'), literal(['park', 'garden']))`.
 */
export function call(operator: string, ...args: ExpressionInput[]): Expression {
  const json: JsonValue[] = [operator];
  for (const arg of args) {
    json.push(jsonOf(arg));
  }
  return new Expression(json);
}

/**
 * A literal value. Arrays and objects need it, since the style reads a bare
 * array as an expression: `literal(['Open Sans Regular'])`.
 */
export function literal(value: JsonValue): Expression {
  return new Expression(['literal', value]);
}

// Feature data and inputs

/** The feature's property `name`, or of `object` when given. */
export function get(name: ExpressionInput, object?: Expression): Expression {
  return object === undefined ? call('get', name) : call('get', name, object);
}

/** Whether the feature has the property `name`, or `object` does when given. */
export function has(name: ExpressionInput, object?: Expression): Expression {
  return object === undefined ? call('has', name) : call('has', name, object);
}

/** The feature's state property `name`. Only paint properties can read it. */
export function featureState(name: ExpressionInput): Expression {
  return call('feature-state', name);
}

/**
 * The style's global state property `name`, which the app can set through
 * `MapController.withFfiMap()`. The library reserves the names that start with
 * `maplibre-arkui:`, such as the one that `fp()` reads.
 */
export function globalState(name: ExpressionInput): Expression {
  return call('global-state', name);
}

/** The feature's properties, as an object. */
export function properties(): Expression {
  return call('properties');
}

/** The feature's ID. */
export function id(): Expression {
  return call('id');
}

/** The feature's geometry type: `'Point'`, `'LineString'`, or `'Polygon'`. */
export function geometryType(): Expression {
  return call('geometry-type');
}

/**
 * The map's zoom level. MapLibre accepts it only as the input of a top-level
 * `interpolate()` or `step()`.
 */
export function zoom(): Expression {
  return call('zoom');
}

/** The heatmap's density at a pixel, for `heatmap-color`. */
export function heatmapDensity(): Expression {
  return call('heatmap-density');
}

/** The progress along a line, for `line-gradient`. */
export function lineProgress(): Expression {
  return call('line-progress');
}

// Ramps

/**
 * How `interpolate()` computes the values between its stops. Create one
 * with `linear()`, `exponential()`, or `cubicBezier()`.
 */
export class Interpolation {
  private readonly json: JsonValue[];

  /** Creates an interpolation from its style-spec JSON, such as `['linear']`. */
  constructor(json: JsonValue[]) {
    this.json = json;
  }

  /** The style-spec JSON, which `JSON.stringify` writes for the interpolation. */
  toJSON(): JsonValue[] {
    return this.json;
  }
}

/** Interpolates linearly. */
export function linear(): Interpolation {
  return new Interpolation(['linear']);
}

/**
 * Interpolates exponentially. The higher `base` is, the more the output rises
 * toward the end of each range; 1 is linear.
 */
export function exponential(base: number): Interpolation {
  return new Interpolation(['exponential', base]);
}

/** Interpolates along the cubic Bézier curve with these control points, each from 0 to 1. */
export function cubicBezier(x1: number, y1: number, x2: number, y2: number): Interpolation {
  return new Interpolation(['cubic-bezier', x1, y1, x2, y2]);
}

/** An input value and the output at it, for `interpolate()` and `step()`. */
export type Stop = [number, ExpressionInput];

// Appends the stops to `json`, the start of a ramp, as the spec's flat list.
function ramp(json: JsonValue[], stops: Stop[]): Expression {
  for (const stop of stops) {
    json.push(stop[0]);
    json.push(jsonOf(stop[1]));
  }
  return new Expression(json);
}

/**
 * Interpolates between the outputs of `stops`, whose inputs must increase.
 * Outside them, it's the first or the last output. Outputs can be numbers,
 * colors, or arrays of numbers.
 *
 * ```ts
 * interpolate(exponential(2), zoom(), [[10, 1], [18, 32]])
 * ```
 */
export function interpolate(type: Interpolation, input: ExpressionInput,
  stops: Stop[]): Expression {
  return ramp(['interpolate', type.toJSON(), jsonOf(input)], stops);
}

/** Interpolates colors like `interpolate()`, in the HCL color space. */
export function interpolateHcl(type: Interpolation, input: ExpressionInput,
  stops: Stop[]): Expression {
  return ramp(['interpolate-hcl', type.toJSON(), jsonOf(input)], stops);
}

/** Interpolates colors like `interpolate()`, in the CIELAB color space. */
export function interpolateLab(type: Interpolation, input: ExpressionInput,
  stops: Stop[]): Expression {
  return ramp(['interpolate-lab', type.toJSON(), jsonOf(input)], stops);
}

/**
 * The output of the last stop whose input is at most `input`, or `fallback`
 * below the first stop. The stops' inputs must increase.
 *
 * ```ts
 * step(get('population'), 2, [[1000, 4], [100000, 8]])
 * ```
 */
export function step(input: ExpressionInput, fallback: ExpressionInput,
  stops: Stop[]): Expression {
  return ramp(['step', jsonOf(input), jsonOf(fallback)], stops);
}

// Decisions

/** A label of a `match()` case: one value, or any of several. */
export type MatchLabel = string | number | string[] | number[];

/** A label and the output of a `match()` when the input equals it. */
export type MatchCase = [MatchLabel, ExpressionInput];

/**
 * The output of the case whose label equals `input`, or `fallback`. Labels
 * are plain strings or numbers, all of one type, each in one case.
 *
 * ```ts
 * match(get('class'), [['park', '#8c8'], [['lake', 'river'], '#88c']], '#ccc')
 * ```
 */
export function match(input: ExpressionInput, cases: MatchCase[],
  fallback: ExpressionInput): Expression {
  const json: JsonValue[] = ['match', jsonOf(input)];
  for (const item of cases) {
    json.push(item[0]);
    json.push(jsonOf(item[1]));
  }
  json.push(jsonOf(fallback));
  return new Expression(json);
}

/** A condition and the output of `cases()` when it's the first true one. */
export type Condition = [ExpressionInput, ExpressionInput];

/**
 * The output of the first true condition, or `fallback`: the style spec's
 * `case`, which is a reserved word in ArkTS.
 *
 * ```ts
 * cases([[not(has('mag')), '#888'], [gt(get('mag'), 5), '#f00']], '#fa0')
 * ```
 */
export function cases(conditions: Condition[], fallback: ExpressionInput): Expression {
  const json: JsonValue[] = ['case'];
  for (const condition of conditions) {
    json.push(jsonOf(condition[0]));
    json.push(jsonOf(condition[1]));
  }
  json.push(jsonOf(fallback));
  return new Expression(json);
}

/** The first of `values` that isn't null. */
export function coalesce(...values: ExpressionInput[]): Expression {
  return call('coalesce', ...values);
}

/** Whether `a` equals `b`. */
export function eq(a: ExpressionInput, b: ExpressionInput): Expression {
  return call('==', a, b);
}

/** Whether `a` doesn't equal `b`. */
export function neq(a: ExpressionInput, b: ExpressionInput): Expression {
  return call('!=', a, b);
}

/** Whether `a` is less than `b`. */
export function lt(a: ExpressionInput, b: ExpressionInput): Expression {
  return call('<', a, b);
}

/** Whether `a` is at most `b`. */
export function lte(a: ExpressionInput, b: ExpressionInput): Expression {
  return call('<=', a, b);
}

/** Whether `a` is greater than `b`. */
export function gt(a: ExpressionInput, b: ExpressionInput): Expression {
  return call('>', a, b);
}

/** Whether `a` is at least `b`. */
export function gte(a: ExpressionInput, b: ExpressionInput): Expression {
  return call('>=', a, b);
}

/** Whether `value` is false. */
export function not(value: ExpressionInput): Expression {
  return call('!', value);
}

/** Whether every one of `values` is true. */
export function all(...values: ExpressionInput[]): Expression {
  return call('all', ...values);
}

/** Whether any of `values` is true. */
export function any(...values: ExpressionInput[]): Expression {
  return call('any', ...values);
}

// Math

/** The sum of `values`. */
export function add(...values: ExpressionInput[]): Expression {
  return call('+', ...values);
}

/** `a` minus `b`. */
export function subtract(a: ExpressionInput, b: ExpressionInput): Expression {
  return call('-', a, b);
}

/** The product of `values`. */
export function multiply(...values: ExpressionInput[]): Expression {
  return call('*', ...values);
}

/** `a` divided by `b`. */
export function divide(a: ExpressionInput, b: ExpressionInput): Expression {
  return call('/', a, b);
}

/** The remainder of `a` divided by `b`. */
export function mod(a: ExpressionInput, b: ExpressionInput): Expression {
  return call('%', a, b);
}

/** `base` to the power of `exponent`. */
export function pow(base: ExpressionInput, exponent: ExpressionInput): Expression {
  return call('^', base, exponent);
}

/**
 * `value`, a size in vp, scaled by the font scale, as ArkUI scales a size in
 * fp: for `text-size`, so labels follow the user's font size setting as the
 * app's text does.
 *
 * ```ts
 * fp(14)
 * interpolate(linear(), zoom(), [[10, fp(12)], [16, fp(18)]])
 * ```
 *
 * It multiplies `value` by the global state property
 * `maplibre-arkui:font-scale`, or by 1 where nothing sets it. `MaplibreMap`
 * sets it on each style it loads, to `fp2px(1) / vp2px(1)` of its UI context,
 * and again when that changes; `snapshot()` sets it to its `fontScale`. Like
 * ArkUI's text, it follows the user's setting only in an app that opts in with
 * `"fontSizeScale": "followSystem"` in its configuration profile. Since
 * `zoom()` must be the input of a top-level `interpolate()` or `step()`, scale
 * each stop's output rather than the ramp.
 */
export function fp(value: ExpressionInput): Expression {
  return multiply(value, call('number', globalState(FONT_SCALE_STATE), 1));
}

/** The square root of `value`. */
export function sqrt(value: ExpressionInput): Expression {
  return call('sqrt', value);
}

/** The absolute value of `value`. */
export function abs(value: ExpressionInput): Expression {
  return call('abs', value);
}

/** `value` rounded to the nearest integer, halves away from zero. */
export function round(value: ExpressionInput): Expression {
  return call('round', value);
}

/** The largest integer at most `value`. */
export function floor(value: ExpressionInput): Expression {
  return call('floor', value);
}

/** The smallest integer at least `value`. */
export function ceil(value: ExpressionInput): Expression {
  return call('ceil', value);
}

/** The smallest of `values`. */
export function min(...values: ExpressionInput[]): Expression {
  return call('min', ...values);
}

/** The largest of `values`. */
export function max(...values: ExpressionInput[]): Expression {
  return call('max', ...values);
}

// Conversions and strings

/** The first of `values` that converts to a number, or an error. */
export function toNumber(...values: ExpressionInput[]): Expression {
  return call('to-number', ...values);
}

/** `value` converted to a string. */
export function toString(value: ExpressionInput): Expression {
  return call('to-string', value);
}

/** Whether `value` is truthy. */
export function toBoolean(value: ExpressionInput): Expression {
  return call('to-boolean', value);
}

/** The first of `values` that converts to a color, or an error. */
export function toColor(...values: ExpressionInput[]): Expression {
  return call('to-color', ...values);
}

/** `values` converted to strings and joined. */
export function concat(...values: ExpressionInput[]): Expression {
  return call('concat', ...values);
}

/** `value` in uppercase. */
export function upcase(value: ExpressionInput): Expression {
  return call('upcase', value);
}

/** `value` in lowercase. */
export function downcase(value: ExpressionInput): Expression {
  return call('downcase', value);
}

// Colors, text, and images

/** The color with these red, green, and blue components, from 0 to 255. */
export function rgb(red: ExpressionInput, green: ExpressionInput, blue: ExpressionInput): Expression {
  return call('rgb', red, green, blue);
}

/** The color with these red, green, and blue components, from 0 to 255, and alpha, from 0 to 1. */
export function rgba(red: ExpressionInput, green: ExpressionInput, blue: ExpressionInput,
  alpha: ExpressionInput): Expression {
  return call('rgba', red, green, blue, alpha);
}

/** The style's image named `name`, for `icon-image` or a `format()` section. */
export function image(name: ExpressionInput): Expression {
  return call('image', name);
}

/** A section of `format()` text and how it overrides the layer's text style. */
export interface FormatSection {
  /** The section's text, or an `image()`. */
  text: ExpressionInput;
  /** Scales the layer's `text-size`. */
  fontScale?: ExpressionInput;
  /** The fonts, such as `literal(['Open Sans Bold'])`. */
  textFont?: Expression;
  textColor?: ExpressionInput;
}

/**
 * Text in sections with styles of their own, for `text-field`.
 *
 * ```ts
 * format({ text: get('name') }, { text: '\n' }, { text: get('ref'), fontScale: 0.8 })
 * ```
 */
export function format(...sections: FormatSection[]): Expression {
  const json: JsonValue[] = ['format'];
  for (const section of sections) {
    const options: Record<string, JsonValue> = {};
    if (section.fontScale !== undefined) {
      options['font-scale'] = jsonOf(section.fontScale);
    }
    if (section.textFont !== undefined) {
      options['text-font'] = section.textFont.toJSON();
    }
    if (section.textColor !== undefined) {
      options['text-color'] = jsonOf(section.textColor);
    }
    json.push(jsonOf(section.text));
    json.push(options);
  }
  return new Expression(json);
}
