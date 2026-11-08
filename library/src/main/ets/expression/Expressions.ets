// Style expressions: functions that build the JSON of MapLibre style-spec
// expressions, https://maplibre.org/maplibre-style-spec/expressions/.
//
// Each function is named after its operator in camelCase, such as `featureState`
// for `feature-state`. Symbols get words (`eq` for `==`, `add` for `+`), and
// `case`, a reserved word, is `cases`. Expressions are untyped: MapLibre checks
// an expression's types when it parses it, and a phantom `Expression<T>` would
// check nothing in ArkTS without a brand, or type assertions at every feature
// property with one.

import { StyleImageOptions, StyleImageSource } from '../content/StyleImage';
import { resolveColor } from './internal/Colors';
import { FONT_SCALE_STATE } from './internal/FontScale';
import { attachRefs, colorName, ColorRef, imageName, ImageRef, isResource, setRefs } from './internal/StyleRefs';

/** A JSON value, as a style holds it. */
export type JsonValue = string | number | boolean | null | JsonValue[] | JsonObject;

/** A JSON object. */
export interface JsonObject extends Record<string, JsonValue> {}

/**
 * An argument to an expression function: an expression, or a plain number,
 * string, boolean, or null. Wrap arrays and objects in `literal()`.
 */
export type ExpressionInput = Expression | string | number | boolean | null;

/**
 * A style expression. Expressions are immutable. The map checks an expression
 * when it uses it; an invalid expression in the map's content is reported to
 * `onError`.
 */
export class Expression {
  private readonly json: JsonValue;
  private readonly key: string;

  /** Creates an expression from its style-spec JSON, such as `['get', 'name']`. */
  constructor(json: JsonValue) {
    this.key = JSON.stringify(json);
    this.json = JSON.parse(this.key) as JsonValue;
  }

  /** The expression's style-spec JSON. */
  toJSON(): JsonValue {
    return this.json;
  }

  /** The expression's style-spec JSON as text. */
  toString(): string {
    return this.key;
  }
}

function jsonOf(input: ExpressionInput): JsonValue {
  return input instanceof Expression ? input.toJSON() : input;
}

// An expression from `json`, with the colors and images of the inputs that it
// was built from.
function build(json: JsonValue, inputs: (ExpressionInput | undefined)[]): Expression {
  const expression = new Expression(json);
  const expressions: Object[] = [];
  for (const input of inputs) {
    if (input instanceof Expression) {
      expressions.push(input);
    }
  }
  attachRefs(expression, expressions);
  return expression;
}

/** Any style-spec operator, with arguments, for an operator that has no function. */
export function call(operator: string, ...args: ExpressionInput[]): Expression {
  const json: JsonValue[] = [operator];
  for (const arg of args) {
    json.push(jsonOf(arg));
  }
  return build(json, args);
}

/** The `literal` operator: a value as it is. Array and object arguments need it. */
export function literal(value: JsonValue): Expression {
  return new Expression(['literal', value]);
}

// Feature data and inputs

/** The `get` operator: a property of the feature, or of `object` when given. */
export function get(name: ExpressionInput, object?: Expression): Expression {
  return object === undefined ? call('get', name) : call('get', name, object);
}

/** The `has` operator: whether the feature, or `object` when given, has a property. */
export function has(name: ExpressionInput, object?: Expression): Expression {
  return object === undefined ? call('has', name) : call('has', name, object);
}

/** The `feature-state` operator: a value of the feature's state. */
export function featureState(name: ExpressionInput): Expression {
  return call('feature-state', name);
}

/** The `global-state` operator: a global state property of the style. */
export function globalState(name: ExpressionInput): Expression {
  return call('global-state', name);
}

/** The `properties` operator: the feature's properties, as an object. */
export function properties(): Expression {
  return call('properties');
}

/** The `id` operator: the feature's ID. */
export function id(): Expression {
  return call('id');
}

/** The `geometry-type` operator: `'Point'`, `'LineString'`, or `'Polygon'`. */
export function geometryType(): Expression {
  return call('geometry-type');
}

/** The `zoom` operator: the map's zoom level. */
export function zoom(): Expression {
  return call('zoom');
}

/** The `heatmap-density` operator. */
export function heatmapDensity(): Expression {
  return call('heatmap-density');
}

/** The `line-progress` operator. */
export function lineProgress(): Expression {
  return call('line-progress');
}

// Ramps

/** How `interpolate()` computes values between stops. */
export class Interpolation {
  private readonly json: JsonValue[];

  /** Creates an interpolation from its style-spec JSON, such as `['linear']`. */
  constructor(json: JsonValue[]) {
    this.json = json;
  }

  /** The interpolation's style-spec JSON. */
  toJSON(): JsonValue[] {
    return this.json;
  }
}

/** Interpolates linearly. */
export function linear(): Interpolation {
  return new Interpolation(['linear']);
}

/** Interpolates exponentially with `base`. */
export function exponential(base: number): Interpolation {
  return new Interpolation(['exponential', base]);
}

/** Interpolates along a cubic Bézier curve. */
export function cubicBezier(x1: number, y1: number, x2: number, y2: number): Interpolation {
  return new Interpolation(['cubic-bezier', x1, y1, x2, y2]);
}

/** An input and its output, for `interpolate()` and `step()`. */
export type Stop = [number, ExpressionInput];

// Appends the stops to `json`, the start of a ramp, as the spec's flat list.
function ramp(json: JsonValue[], inputs: ExpressionInput[], stops: Stop[]): Expression {
  for (const stop of stops) {
    json.push(stop[0]);
    json.push(jsonOf(stop[1]));
    inputs.push(stop[1]);
  }
  return build(json, inputs);
}

/** The `interpolate` operator: a value between the outputs of the stops around `input`. */
export function interpolate(type: Interpolation, input: ExpressionInput,
  stops: Stop[]): Expression {
  return ramp(['interpolate', type.toJSON(), jsonOf(input)], [input], stops);
}

/** The `interpolate-hcl` operator. */
export function interpolateHcl(type: Interpolation, input: ExpressionInput,
  stops: Stop[]): Expression {
  return ramp(['interpolate-hcl', type.toJSON(), jsonOf(input)], [input], stops);
}

/** The `interpolate-lab` operator. */
export function interpolateLab(type: Interpolation, input: ExpressionInput,
  stops: Stop[]): Expression {
  return ramp(['interpolate-lab', type.toJSON(), jsonOf(input)], [input], stops);
}

/** The `step` operator: the output of the last stop at or below `input`, or `fallback`. */
export function step(input: ExpressionInput, fallback: ExpressionInput,
  stops: Stop[]): Expression {
  return ramp(['step', jsonOf(input), jsonOf(fallback)], [input, fallback], stops);
}

// Decisions

/** The label of a `match()` case: one value, or several. */
export type MatchLabel = string | number | string[] | number[];

/** A `match()` case: a label and its output. */
export type MatchCase = [MatchLabel, ExpressionInput];

/** The `match` operator: the output of the case whose label equals `input`, or `fallback`. */
export function match(input: ExpressionInput, cases: MatchCase[],
  fallback: ExpressionInput): Expression {
  const json: JsonValue[] = ['match', jsonOf(input)];
  const inputs: ExpressionInput[] = [input, fallback];
  for (const item of cases) {
    json.push(item[0]);
    json.push(jsonOf(item[1]));
    inputs.push(item[1]);
  }
  json.push(jsonOf(fallback));
  return build(json, inputs);
}

/** A `cases()` case: a condition and its output. */
export type Condition = [ExpressionInput, ExpressionInput];

/** The `case` operator: the output of the first true condition, or `fallback`. */
export function cases(conditions: Condition[], fallback: ExpressionInput): Expression {
  const json: JsonValue[] = ['case'];
  const inputs: ExpressionInput[] = [fallback];
  for (const condition of conditions) {
    json.push(jsonOf(condition[0]));
    json.push(jsonOf(condition[1]));
    inputs.push(condition[0], condition[1]);
  }
  json.push(jsonOf(fallback));
  return build(json, inputs);
}

/** The `coalesce` operator: the first value that isn't null. */
export function coalesce(...values: ExpressionInput[]): Expression {
  return call('coalesce', ...values);
}

/** The `==` operator: whether `a` equals `b`. */
export function eq(a: ExpressionInput, b: ExpressionInput): Expression {
  return call('==', a, b);
}

/** The `!=` operator: whether `a` doesn't equal `b`. */
export function neq(a: ExpressionInput, b: ExpressionInput): Expression {
  return call('!=', a, b);
}

/** The `<` operator: whether `a` is less than `b`. */
export function lt(a: ExpressionInput, b: ExpressionInput): Expression {
  return call('<', a, b);
}

/** The `<=` operator: whether `a` is at most `b`. */
export function lte(a: ExpressionInput, b: ExpressionInput): Expression {
  return call('<=', a, b);
}

/** The `>` operator: whether `a` is greater than `b`. */
export function gt(a: ExpressionInput, b: ExpressionInput): Expression {
  return call('>', a, b);
}

/** The `>=` operator: whether `a` is at least `b`. */
export function gte(a: ExpressionInput, b: ExpressionInput): Expression {
  return call('>=', a, b);
}

/** The `!` operator: whether `value` is false. */
export function not(value: ExpressionInput): Expression {
  return call('!', value);
}

/** The `all` operator: whether every value is true. */
export function all(...values: ExpressionInput[]): Expression {
  return call('all', ...values);
}

/** The `any` operator: whether any value is true. */
export function any(...values: ExpressionInput[]): Expression {
  return call('any', ...values);
}

// Math

/** The `+` operator: the sum of the values. */
export function add(...values: ExpressionInput[]): Expression {
  return call('+', ...values);
}

/** The `-` operator: `a` minus `b`. */
export function subtract(a: ExpressionInput, b: ExpressionInput): Expression {
  return call('-', a, b);
}

/** The `*` operator: the product of the values. */
export function multiply(...values: ExpressionInput[]): Expression {
  return call('*', ...values);
}

/** The `/` operator: `a` divided by `b`. */
export function divide(a: ExpressionInput, b: ExpressionInput): Expression {
  return call('/', a, b);
}

/** The `%` operator: the remainder of `a` divided by `b`. */
export function mod(a: ExpressionInput, b: ExpressionInput): Expression {
  return call('%', a, b);
}

/** The `^` operator: `base` to the power of `exponent`. */
export function pow(base: ExpressionInput, exponent: ExpressionInput): Expression {
  return call('^', base, exponent);
}

/**
 * Scales a text size by the font scale, as ArkUI's `fp` unit does. A map uses
 * the font scale of its UI context, and `renderSnapshot()` uses its
 * `fontScale`. Not a style-spec operator.
 */
export function fp(value: ExpressionInput): Expression {
  return multiply(value, call('number', globalState(FONT_SCALE_STATE), 1));
}

/** The `sqrt` operator: the square root of `value`. */
export function sqrt(value: ExpressionInput): Expression {
  return call('sqrt', value);
}

/** The `abs` operator: the absolute value of `value`. */
export function abs(value: ExpressionInput): Expression {
  return call('abs', value);
}

/** The `round` operator: `value` rounded to the nearest integer. */
export function round(value: ExpressionInput): Expression {
  return call('round', value);
}

/** The `floor` operator: the largest integer at most `value`. */
export function floor(value: ExpressionInput): Expression {
  return call('floor', value);
}

/** The `ceil` operator: the smallest integer at least `value`. */
export function ceil(value: ExpressionInput): Expression {
  return call('ceil', value);
}

/** The `min` operator: the smallest value. */
export function min(...values: ExpressionInput[]): Expression {
  return call('min', ...values);
}

/** The `max` operator: the largest value. */
export function max(...values: ExpressionInput[]): Expression {
  return call('max', ...values);
}

// Conversions and strings

/** The `to-number` operator: the first value that converts to a number. */
export function toNumber(...values: ExpressionInput[]): Expression {
  return call('to-number', ...values);
}

/** The `to-string` operator: `value` as a string. */
export function toString(value: ExpressionInput): Expression {
  return call('to-string', value);
}

/** The `to-boolean` operator: whether `value` is truthy. */
export function toBoolean(value: ExpressionInput): Expression {
  return call('to-boolean', value);
}

/** The `to-color` operator: the first value that converts to a color. */
export function toColor(...values: ExpressionInput[]): Expression {
  return call('to-color', ...values);
}

/** The `concat` operator: the values as strings, joined. */
export function concat(...values: ExpressionInput[]): Expression {
  return call('concat', ...values);
}

/** The `upcase` operator: `value` in uppercase. */
export function upcase(value: ExpressionInput): Expression {
  return call('upcase', value);
}

/** The `downcase` operator: `value` in lowercase. */
export function downcase(value: ExpressionInput): Expression {
  return call('downcase', value);
}

// Colors, text, and images

/** The `rgb` operator: a color from red, green, and blue. */
export function rgb(red: ExpressionInput, green: ExpressionInput, blue: ExpressionInput): Expression {
  return call('rgb', red, green, blue);
}

/** The `rgba` operator: a color from red, green, blue, and alpha. */
export function rgba(red: ExpressionInput, green: ExpressionInput, blue: ExpressionInput,
  alpha: ExpressionInput): Expression {
  return call('rgba', red, green, blue, alpha);
}

/**
 * A color from ArkUI, such as `Color.Red`, `'#AARRGGBB'`, or
 * `$r('app.color.accent')`, for a color property or expression. Strings follow
 * ArkUI's color formats, not the style spec's. A resource color follows the
 * system's color mode. Not a style-spec operator.
 *
 * Throws an `Error` for a color that ArkUI can't resolve.
 */
export function color(value: ResourceColor): Expression {
  const current = resolveColor(value).rgba();
  if (!isResource(value)) {
    return new Expression(['to-color', current]);
  }
  const resource = value as Resource;
  const name = colorName(resource);
  const expression = new Expression(['to-color', ['global-state', name], current]);
  setRefs(expression, [new ColorRef(name, resource)]);
  return expression;
}

/**
 * The `image` operator. A string or expression names an image of the style. A
 * `StyleImageSource` is an image that the map adds to the style, drawn as
 * `options` say, while a layer uses it. Uses of the same source with the same
 * options share one image, and an image from a resource follows the system's
 * color mode.
 *
 * Don't release a pixel map while a layer uses it. The map doesn't see changes
 * to a pixel map's pixels, so pass a new pixel map to change them. The map's
 * content waits to change until the map has drawn its images. An image that
 * the map can't draw is reported as the content's errors are, and its layers
 * draw without it.
 *
 * Throws an `Error` for `options` with a string or expression.
 */
export function image(value: ExpressionInput | StyleImageSource, options?: StyleImageOptions): Expression {
  if (value === null || typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean' ||
    value instanceof Expression) {
    if (options !== undefined) {
      throw new Error('image() takes options only with a pixel map, a resource, or a drawable descriptor, not ' +
        JSON.stringify(value));
    }
    return call('image', value as ExpressionInput);
  }
  const source = value as StyleImageSource;
  const drawAsSdf = options?.drawAsSdf ?? false;
  const name = imageName(source, drawAsSdf);
  const expression = new Expression(['image', name]);
  setRefs(expression, [new ImageRef(name, source, drawAsSdf)]);
  return expression;
}

/** A section of `format()` text, with its own text style. */
export interface FormatSection {
  /** The text, or an `image()`. */
  text: ExpressionInput;
  /** A factor for the layer's `text-size`. */
  fontScale?: ExpressionInput;
  /** The fonts. */
  textFont?: Expression;
  /** The text color. */
  textColor?: ExpressionInput;
}

/** The `format` operator: text in sections with their own styles. */
export function format(...sections: FormatSection[]): Expression {
  const json: JsonValue[] = ['format'];
  const inputs: (ExpressionInput | undefined)[] = [];
  for (const section of sections) {
    inputs.push(section.text, section.fontScale, section.textFont, section.textColor);
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
  return build(json, inputs);
}
