import 'package:wambito/local/memory_store.dart';

import 'store_contract.dart';

void main() {
  runStoreContract('memory store', () async => createMemoryStore());
}
