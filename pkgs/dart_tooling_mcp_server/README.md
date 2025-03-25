Experimental MCP server which exposes Dart development tool actions to clients.

## Status

WIP

## Using this package

To use this package, you will need to compile the `bin/main.dart` script to exe
(`dart compile bin/main.dart`) and use the compiled path as the command in your
MCP server config.

### With Cursor

Go to Cursor -> Settings -> Cursor Settings and select "MCP".

Then, click "Add new global MCP server". Put in the full path to the executable
you created in the first step as the "command".

If you are directly editing your mcp.json file, it should look like this:

```yaml
{
  "mcpServers": {
    "dart_mcp": {
      "command": "<path-to-compiled-exe>",
      "args": []
    }
  }
}
```

## Debugging MCP Servers

See https://modelcontextprotocol.io/docs/tools/inspector.

The setup here is basically the same as the cursor config, launch the inspector
with no options, and then plug in the executable path and DTD Uri into the
connection window.

You should then see all available functionality from the server.
