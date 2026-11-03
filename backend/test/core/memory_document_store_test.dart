import 'package:test/test.dart';

import '../support/document_store_contract.dart';
import '../support/memory_document_store.dart';

void main() {
  group('MemoryDocumentStore contract', () {
    documentStoreContract(MemoryDocumentStore.new);
  });
}
