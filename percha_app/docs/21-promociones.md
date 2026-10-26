# 21 · Promociones en la app

- **Más → Promociones** (`catalog.write`): crear o editar porcentajes y "lleva X, paga Y",
  por todo, categorías o productos, con vigencia y pausa.
- **POS**: el ticket calcula las promociones al instante con la foto local (mismo motor que la
  API: `pos/domain/promotions.dart`). Cada línea muestra su promoción ("2x1 tops · − S/ 49.90")
  y el ticket la fila **Promociones**. El descuento manual se aplica después.
- **Antes de cobrar**, el POS pide al servidor el total exacto (`/sales/quote`). Si difiere
  (una promoción empezó o terminó, cambió un precio), muestra **"El total cambió"** y cobra el
  correcto solo si la cajera confirma. Sin conexión, cobra el total local.
- Pruebas: `test/promotions_test.dart` corre los mismos casos que la API
  (`test/fixtures/promotions-vectors.json`, copia del archivo del backend).
