Experimental MCP server which exposes Dart development tool actions to clients.

## Status

WIP

## Using this package

To use this package, will need to compile the `bin/main.dart` script to exe
(`dart compile bin/main.dart`) and use the compiled path as the command in your
MCP server config.

The command also requires a DTD Uri to connect to your current debug session,
so the first argument will have to be that URI. In VsCode, you can get this
by using the "Copy DTD URI to Clipboard" command from the Dart extension.

### With Cursor

Go to Cursor -> Settings -> Cursor Settings and select "MCP".

Then, click "Add new global MCP server". Put in the full path to the executable
you created in the first step, and paste in the DTD uri into the arguments
section.

If you are directly editing your mcp.json file, it should look like this:

```yaml
{
  "mcpServers": {
    "dart_mcp": {
      "command": "<path-to-compiled-exe>",
      "args": [
        "<your-dtd-uri>"
      ]
    }
  }
}
```
