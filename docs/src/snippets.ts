/**
 * Extracts a `// #region <name>` block from a file of the demo's
 * `ets/docs/`, imported with `?raw`.
 *
 * The demo build compiles those files, so the site's examples keep to the API.
 * Named regions keep the pages' references valid when lines move, and a
 * missing region fails the site build.
 */
export function region(source: string, name: string): string {
  const lines = source.split("\n");
  const start = lines.findIndex((line) => isMarker(line, "region", name));
  if (start === -1) {
    throw new Error(`snippet region "${name}" has no "// #region ${name}"`);
  }
  const end = lines.findIndex(
    (line, index) => index > start && isMarker(line, "endregion", name),
  );
  if (end === -1) {
    throw new Error(`snippet region "${name}" has no "// #endregion ${name}"`);
  }

  const body = lines
    .slice(start + 1, end)
    .filter(
      (line) => !isMarker(line, "region") && !isMarker(line, "endregion"),
    );

  return dedent(trimBlankEdges(body)).join("\n");
}

function isMarker(line: string, kind: string, name?: string): boolean {
  const suffix = name === undefined ? "\\s*\\S*" : `\\s+${escape(name)}`;
  return new RegExp(`^\\s*//\\s*#${kind}${suffix}\\s*$`).test(line);
}

function escape(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function trimBlankEdges(lines: string[]): string[] {
  let first = 0;
  let last = lines.length;
  while (first < last && lines[first]?.trim() === "") first++;
  while (last > first && lines[last - 1]?.trim() === "") last--;
  return lines.slice(first, last);
}

function dedent(lines: string[]): string[] {
  const indents = lines
    .filter((line) => line.trim() !== "")
    .map((line) => line.length - line.trimStart().length);
  const common = indents.length === 0 ? 0 : Math.min(...indents);
  return lines.map((line) => line.slice(common));
}
