import 'package:mcp_dart/mcp_dart.dart';
import 'package:mcp_dart/src/shared/transport.dart';
import 'dart:async';

/// ClientManager handles managing multiple MCP clients.
class ClientManager {
  /// Create a new ClientManager instance.
  ClientManager({this.defaultClientName = 'client'});

  /// The name to use for clients if not specified
  final String defaultClientName;
  
  /// Collection of managed clients
  final Map<String, Client> _clients = {};
  
  /// Collection of transports for proper cleanup
  final Map<String, Transport> _transports = {};
  
  /// Add a client
  void addClient(Client client, String clientId) {
    _clients[clientId] = client;
  }
  
  /// Get a client by ID
  Client? getClient(String clientId) {
    return _clients[clientId];
  }
  
  /// Get all client IDs
  List<String> get clientIds => _clients.keys.toList();
  
  /// Remove a client
  Client? removeClient(String clientId) {
    _transports.remove(clientId);
    return _clients.remove(clientId);
  }
  
  /// Connect a client by ID using HTTP transport
  Future<void> connectHttp(String clientId, String url) async {
    final client = _clients[clientId];
    if (client == null) {
      throw Exception('Client not found: $clientId');
    }
    
    print('Connecting client $clientId to $url...');
    
    // Create the transport
    final transport = StreamableHttpClientTransport(
      Uri.parse(url),
    );
    
    // Store the transport for proper cleanup
    _transports[clientId] = transport;
    
    // Set error handler
    client.onerror = (error) {
      print('Client error ($clientId): $error');
    };

    client.onclose = () {
      print('Client closed ($clientId)');
    };
    
    // Connect the client
    await client.connect(transport);
    
    // Get session ID if available
    final sessionId = transport.sessionId;
    if (sessionId != null) {
      print('Connected with session ID: $sessionId');
    }
    
    print('\nServer capabilities will be visible in method calls');
  }
  
  /// Connect a client by ID using stdio transport
  Future<void> connectStdio(String clientId, String command, String args) async {
    final client = _clients[clientId];
    if (client == null) {
      throw Exception('Client not found: $clientId');
    }
    
    print('Connecting client $clientId via stdio to command: $command $args...');
    
    // Create a transport from a server process
    final serverParams = StdioServerParameters(
      command: command,
      args: args.split(' '),
    );
    
    final transport = StdioClientTransport(serverParams);
    
    // Store the transport for proper cleanup
    _transports[clientId] = transport;
    
    // Set error handler
    client.onerror = (error) {
      print('Client error ($clientId): $error');
    };
    
    // Connect the client
    await client.connect(transport);
    print('Connected via stdio');
    
    print('\nServer capabilities will be visible in method calls');
  }
  
  /// Disconnect all clients
  Future<void> disconnectAll() async {
    final futures = <Future>[];
    for (final entry in _clients.entries) {
      try {
        final clientId = entry.key;
        final client = entry.value;
        print('Attempting to disconnect client $clientId');
        
        // First terminate HTTP sessions if available
        final transport = _transports[clientId];
        if (transport is StreamableHttpClientTransport) {
          try {
            // Try to terminate the session properly
            print('Terminating HTTP session for client $clientId');
            await transport.terminateSession();
          } catch (e) {
            print('Error terminating session for $clientId: $e');
          }
        }
        
        // Close the client
        futures.add(client.close());
        
        // Explicitly close the transport
        if (transport != null) {
          try {
            print('Closing transport for client $clientId');
            await transport.close();
          } catch (e) {
            print('Error closing transport for $clientId: $e');
          }
        }
      } catch (e) {
        print('Error disconnecting client ${entry.key}: $e');
      }
    }
    
    // Wait for all disconnect operations to complete
    await Future.wait(futures);
    _transports.clear(); // Clear the transports map
    _clients.clear(); // Clear the clients map to release references
  }
}

/// Doug is a simple interface for working with MCP clients.
class Doug {
  /// Create a new Doug instance.
  Doug({String defaultClientName = 'doug-client'}) 
    : _clientManager = ClientManager(defaultClientName: defaultClientName);

  /// The client manager that handles all clients
  final ClientManager _clientManager;

  /// Close all clients
  Future<void> close() async {
    return _clientManager.disconnectAll();
  }
  
  /// Create and add a client with HTTP transport
  Future<Client> addHttpClient(String url, {String? name, String? clientId}) async {
    final clientName = name ?? _clientManager.defaultClientName;
    final id = clientId ?? url;
    
    final client = Client(Implementation(name: clientName, version: '1.0.0'));
    _clientManager.addClient(client, id);
    await _clientManager.connectHttp(id, url);
    return client;
  }
  
  /// Create and add a client with stdio transport
  Future<Client> addStdioClient(String command, String args, {String? name, String? clientId}) async {
    final clientName = name ?? _clientManager.defaultClientName;
    final id = clientId ?? '$command-$args';
    
    final client = Client(Implementation(name: clientName, version: '1.0.0'));
    _clientManager.addClient(client, id);
    await _clientManager.connectStdio(id, command, args);
    return client;
  }

  /// Get the capabilities of all clients
  Future<List<ServerCapabilities>> getClientCapabilities() async {
    final capabilities = <ServerCapabilities>[];
    for (final clientId in _clientManager.clientIds) {
      final client = _clientManager.getClient(clientId);
      if (client == null) {
        throw Exception('Client not found: $clientId');
      }
      final serverCapabilities = client.getServerCapabilities();
      if (serverCapabilities == null) {
        throw Exception('Server capabilities not found for client: $clientId');
      }
      capabilities.add(serverCapabilities);
    }
    return capabilities;
  }

  /// Get resources from all clients
  Future<List<ResourceContents>> getResourceValues(List<String> resourceUris) async {
    final resources = <ResourceContents>[];
    for (final clientId in _clientManager.clientIds) {
      final client = _clientManager.getClient(clientId);
      if (client == null) {
        throw Exception('Client not found: $clientId');
      }
      final resourceResults = await Future.wait(resourceUris.map((resourceUris) => client.readResource(
        ReadResourceRequestParams(
          uri: resourceUris,
        ),
      )));

      final resourceValues = resourceResults.map((e) => e.contents).expand((e) => e).toList();

      resources.addAll(resourceValues);
    }
    return resources;
  }
}
