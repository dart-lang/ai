// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// ignore_for_file: lines_longer_than_80_chars

import 'package:dart_mcp/src/api/api.dart';
import 'package:test/test.dart';

void main() {
  // Helper to make assertions cleaner
  void expectFailures(
    Schema schema,
    Object? data,
    List<ValidationError> expected, {
    String? reason,
  }) {
    final result = schema.validate(data);
    // The validate method returns unique failures, so order doesn't matter for comparison.
    expect(
      result.toSet(),
      equals(expected.toSet()),
      reason: reason ?? 'Data: $data',
    );
  }

  group('Schemas', () {
    test('ObjectSchema', () {
      final schema = ObjectSchema(
        title: 'Foo',
        description: 'Bar',
        patternProperties: {'^foo': StringSchema()},
        properties: {'foo': StringSchema(), 'bar': IntegerSchema()},
        required: ['foo'],
        additionalProperties: false,
        unevaluatedProperties: true,
        propertyNames: StringSchema(pattern: r'^[a-z]+$'),
        minProperties: 1,
        maxProperties: 2,
      );
      expect(schema, {
        'type': 'object',
        'title': 'Foo',
        'description': 'Bar',
        'patternProperties': {
          '^foo': {'type': 'string'},
        },
        'properties': {
          'foo': {'type': 'string'},
          'bar': {'type': 'integer'},
        },
        'required': ['foo'],
        'additionalProperties': false,
        'unevaluatedProperties': true,
        'propertyNames': {'type': 'string', 'pattern': r'^[a-z]+$'},
        'minProperties': 1,
        'maxProperties': 2,
      });
    });

    test('StringSchema', () {
      final schema = StringSchema(
        title: 'Foo',
        description: 'Bar',
        minLength: 1,
        maxLength: 10,
        pattern: r'^[a-z]+$',
      );
      expect(schema, {
        'type': 'string',
        'title': 'Foo',
        'description': 'Bar',
        'minLength': 1,
        'maxLength': 10,
        'pattern': r'^[a-z]+$',
      });
    });

    test('NumberSchema', () {
      final schema = NumberSchema(
        title: 'Foo',
        description: 'Bar',
        minimum: 1,
        maximum: 10,
        exclusiveMinimum: 0,
        exclusiveMaximum: 11,
        multipleOf: 2,
      );
      expect(schema, {
        'type': 'number',
        'title': 'Foo',
        'description': 'Bar',
        'minimum': 1,
        'maximum': 10,
        'exclusiveMinimum': 0,
        'exclusiveMaximum': 11,
        'multipleOf': 2,
      });
    });

    test('IntegerSchema', () {
      final schema = IntegerSchema(
        title: 'Foo',
        description: 'Bar',
        minimum: 1,
        maximum: 10,
        exclusiveMinimum: 0,
        exclusiveMaximum: 11,
        multipleOf: 2,
      );
      expect(schema, {
        'type': 'integer',
        'title': 'Foo',
        'description': 'Bar',
        'minimum': 1,
        'maximum': 10,
        'exclusiveMinimum': 0,
        'exclusiveMaximum': 11,
        'multipleOf': 2,
      });
    });

    test('BooleanSchema', () {
      final schema = BooleanSchema(title: 'Foo', description: 'Bar');
      expect(schema, {'type': 'boolean', 'title': 'Foo', 'description': 'Bar'});
    });

    test('NullSchema', () {
      final schema = NullSchema(title: 'Foo', description: 'Bar');
      expect(schema, {'type': 'null', 'title': 'Foo', 'description': 'Bar'});
    });

    test('ListSchema', () {
      final schema = ListSchema(
        title: 'Foo',
        description: 'Bar',
        items: StringSchema(),
        prefixItems: [IntegerSchema(), BooleanSchema()],
        unevaluatedItems: false,
        minItems: 1,
        maxItems: 10,
        uniqueItems: true,
      );
      expect(schema, {
        'type': 'array',
        'title': 'Foo',
        'description': 'Bar',
        'items': {'type': 'string'},
        'prefixItems': [
          {'type': 'integer'},
          {'type': 'boolean'},
        ],
        'unevaluatedItems': false,
        'minItems': 1,
        'maxItems': 10,
        'uniqueItems': true,
      });
    });

    test('Schema', () {
      final schema = Schema.combined(
        type: JsonType.bool,
        title: 'Foo',
        description: 'Bar',
        allOf: [StringSchema(), IntegerSchema()],
        anyOf: [StringSchema(), IntegerSchema()],
        oneOf: [StringSchema(), IntegerSchema()],
        not: [StringSchema()],
      );
      expect(schema, {
        'type': 'boolean',
        'title': 'Foo',
        'description': 'Bar',
        'allOf': [
          {'type': 'string'},
          {'type': 'integer'},
        ],
        'anyOf': [
          {'type': 'string'},
          {'type': 'integer'},
        ],
        'oneOf': [
          {'type': 'string'},
          {'type': 'integer'},
        ],
        'not': [
          {'type': 'string'},
        ],
      });
    });
  });

  group('Schema Validation Tests', () {
    group('Type Mismatch', () {
      test('object schema with non-map data', () {
        expectFailures(Schema.object(), 'not a map', [
          ValidationError.typeMismatch,
        ]);
      });
      test('list schema with non-list data', () {
        expectFailures(Schema.list(), 'not a list', [
          ValidationError.typeMismatch,
        ]);
      });
      test('string schema with non-string data', () {
        expectFailures(Schema.string(), 123, [ValidationError.typeMismatch]);
      });
      test('number schema with non-num data', () {
        expectFailures(Schema.num(), 'not a number', [
          ValidationError.typeMismatch,
        ]);
      });
      test('integer schema with non-int data', () {
        expectFailures(Schema.int(), 'not an int', [
          ValidationError.typeMismatch,
        ]);
      });
      test('integer schema with non-integer num data', () {
        expectFailures(Schema.int(), 10.5, [ValidationError.typeMismatch]);
      });
      test('boolean schema with non-bool data', () {
        expectFailures(Schema.bool(), 'not a bool', [
          ValidationError.typeMismatch,
        ]);
      });
      test('null schema with non-null data', () {
        expectFailures(Schema.nil(), 'not null', [
          ValidationError.typeMismatch,
        ]);
      });
      test('integer schema with integer-like num data (e.g. 10.0)', () {
        expectFailures(IntegerSchema(minimum: 11), 10.0, [
          ValidationError.minimumNotMet,
        ]);
      });
    });

    group('Schema Combinators', () {
      test('allOfNotMet - one sub-schema fails', () {
        final schema = Schema.combined(
          allOf: [StringSchema(minLength: 3), StringSchema(maxLength: 5)],
        );
        expectFailures(schema, 'hi', [
          ValidationError.allOfNotMet,
          ValidationError.minLengthNotMet,
        ]);
      });

      test('allOfNotMet - multiple sub-schemas fail', () {
        final schema = Schema.combined(
          allOf: [
            StringSchema(minLength: 10),
            StringSchema(pattern: '^[a-z]+\$'),
          ],
        );
        expectFailures(schema, 'Short123', [
          ValidationError.allOfNotMet,
          ValidationError.minLengthNotMet,
          ValidationError.patternMismatch,
        ]);
      });

      test('anyOfNotMet - all sub-schemas fail', () {
        final schema = Schema.combined(
          anyOf: [StringSchema(minLength: 5), NumberSchema(minimum: 100)],
        );
        // Data that fails both type checks if types were strictly enforced by anyOf sub-schemas alone
        // However, anyOf itself doesn't enforce type, the subschemas do.
        // If data is `true`, StringSchema(minLength: 5).validate(true) -> [typeMismatch]
        // NumberSchema(minimum: 100).validate(true) -> [typeMismatch]
        // So anyOf fails.
        expectFailures(schema, true, [ValidationError.anyOfNotMet]);
      });

      test('anyOfNotMet - specific failures', () {
        final schema = Schema.combined(
          anyOf: [
            StringSchema(minLength: 5),
            StringSchema(pattern: '^[a-z]+\$'),
          ],
        );
        // "Hi1" fails minLength and pattern.
        // StringSchema(minLength: 5).validate("Hi1") -> [minLengthNotMet]
        // StringSchema(pattern: '^[a-z]+$').validate("Hi1") -> [patternMismatch]
        // Since both fail, anyOf fails.
        expectFailures(schema, 'Hi1', [ValidationError.anyOfNotMet]);
      });

      test('oneOfNotMet - matches none', () {
        // Using minLength/maxLength to simulate exactLength, and minimum/maximum for exactValue
        final s = Schema.combined(
          oneOf: [
            Schema.combined(
              allOf: [StringSchema(minLength: 3), StringSchema(maxLength: 3)],
            ),
            Schema.combined(
              allOf: [NumberSchema(minimum: 10), NumberSchema(maximum: 10)],
            ),
          ],
        );
        expectFailures(s, true, [ValidationError.oneOfNotMet]);
      });

      test('oneOfNotMet - matches multiple', () {
        final schema = Schema.combined(
          oneOf: [StringSchema(maxLength: 10), StringSchema(pattern: 'test')],
        );
        expectFailures(schema, 'test', [ValidationError.oneOfNotMet]);
      });

      test('notConditionViolated - matches 0 sub-schemas in "not" list', () {
        // Current `not` logic: fails if validCount != 1.
        // Data `true` matches 0 schemas in `[StringSchema(), NumberSchema()]`. validCount = 0. 0 != 1 is true.
        final schema = Schema.combined(not: [StringSchema(), NumberSchema()]);
        expectFailures(schema, true, [ValidationError.notConditionViolated]);
      });

      test('notConditionViolated - matches >1 sub-schemas in "not" list', () {
        // Data `"test"` matches both. validCount = 2. 2 != 1 is true.
        final schema = Schema.combined(
          not: [StringSchema(maxLength: 10), StringSchema(pattern: 'test')],
        );
        expectFailures(schema, 'test', [ValidationError.notConditionViolated]);
      });

      test(
        'notConditionViolated - passes if matches exactly 1 (counter-intuitive for "not")',
        () {
          // Data `"hello"` matches `StringSchema(maxLength: 10)` but not `NumberSchema()`.
          // validCount = 1. `1 != 1` is false. No `notConditionViolated`.
          final schema = Schema.combined(
            not: [StringSchema(maxLength: 10), NumberSchema()],
          );
          expectFailures(
            schema,
            'hello',
            [],
          ); // No failure based on current `not` logic
        },
      );
    });

    group('Object Specific', () {
      test('requiredPropertyMissing', () {
        final schema = ObjectSchema(required: ['name']);
        expectFailures(
          schema,
          {'foo': 1},
          [ValidationError.requiredPropertyMissing],
        );
      });

      test('additionalPropertyNotAllowed - boolean false', () {
        final schema = ObjectSchema(
          properties: {'name': StringSchema()},
          additionalProperties: false,
        );
        expectFailures(
          schema,
          {'name': 'test', 'age': 30},
          [ValidationError.additionalPropertyNotAllowed],
        );
      });

      test('additionalPropertyNotAllowed - schema fails', () {
        final schema = ObjectSchema(
          properties: {'name': StringSchema()},
          additionalProperties: StringSchema(minLength: 5),
        );
        expectFailures(
          schema,
          {'name': 'test', 'extra': 'abc'},
          [ValidationError.additionalPropertyNotAllowed],
        );
      });

      test('minPropertiesNotMet', () {
        final schema = ObjectSchema(minProperties: 2);
        expectFailures(schema, {'a': 1}, [ValidationError.minPropertiesNotMet]);
      });

      test('maxPropertiesExceeded', () {
        final schema = ObjectSchema(maxProperties: 1);
        expectFailures(
          schema,
          {'a': 1, 'b': 2},
          [ValidationError.maxPropertiesExceeded],
        );
      });

      test('propertyNamesInvalid', () {
        final schema = ObjectSchema(propertyNames: StringSchema(minLength: 3));
        expectFailures(
          schema,
          {'ab': 1, 'abc': 2},
          [ValidationError.propertyNamesInvalid],
        );
      });

      test('propertyValueInvalid', () {
        final schema = ObjectSchema(
          properties: {'age': IntegerSchema(minimum: 18)},
        );
        // _validate for IntegerSchema(minimum:18) on 10 returns [minimumNotMet]
        // This is then mapped to [propertyValueInvalid]
        expectFailures(
          schema,
          {'age': 10},
          [ValidationError.propertyValueInvalid],
        );
      });

      test('patternPropertyValueInvalid', () {
        final schema = ObjectSchema(
          patternProperties: {r'^x-': IntegerSchema(minimum: 10)},
        );
        expectFailures(
          schema,
          {'x-custom': 5},
          [ValidationError.patternPropertyValueInvalid],
        );
      });

      test('unevaluatedPropertyNotAllowed', () {
        final schema = ObjectSchema(
          properties: {'name': StringSchema()},
          unevaluatedProperties: false,
          // additionalProperties is implicitly null/not defined here
        );
        expectFailures(
          schema,
          {'name': 'test', 'age': 30},
          [ValidationError.unevaluatedPropertyNotAllowed],
        );
      });
    });

    group('List Specific', () {
      test('minItemsNotMet', () {
        final schema = ListSchema(minItems: 2);
        expectFailures(schema, [1], [ValidationError.minItemsNotMet]);
      });

      test('maxItemsExceeded', () {
        final schema = ListSchema(maxItems: 1);
        expectFailures(schema, [1, 2], [ValidationError.maxItemsExceeded]);
      });

      test('uniqueItemsViolated', () {
        final schema = ListSchema(uniqueItems: true);
        expectFailures(
          schema,
          [1, 2, 1],
          [ValidationError.uniqueItemsViolated],
        );
      });

      test('itemInvalid - using items', () {
        final schema = ListSchema(items: IntegerSchema(minimum: 10));
        // _validate for IntegerSchema(minimum:10) on 5 returns [minimumNotMet]
        // The list validation adds itemInvalid if the item's validation is not empty.
        expectFailures(schema, [10, 5, 12], [ValidationError.itemInvalid]);
      });

      test('prefixItemInvalid', () {
        final schema = ListSchema(
          prefixItems: [IntegerSchema(minimum: 10), StringSchema(minLength: 3)],
        );
        expectFailures(schema, [5], [ValidationError.prefixItemInvalid]);
        expectFailures(schema, [10, 'hi'], [ValidationError.prefixItemInvalid]);
      });

      test(
        'unevaluatedItemNotAllowed - after prefixItems, no items schema',
        () {
          final schema = ListSchema(
            prefixItems: [IntegerSchema()],
            unevaluatedItems: false,
          );
          expectFailures(
            schema,
            [10, 'extra'],
            [ValidationError.unevaluatedItemNotAllowed],
          );
        },
      );

      test('unevaluatedItemNotAllowed - no prefixItems, no items schema', () {
        final schema = ListSchema(unevaluatedItems: false);
        expectFailures(
          schema,
          ['extra'],
          [ValidationError.unevaluatedItemNotAllowed],
        );
      });

      test('unevaluatedItemNotAllowed - after items that cover some elements', () {
        // This case implies items schema applies to elements after prefixItems.
        // If unevaluatedItems is false, and an item exists beyond what items schema covers (if items is not for all remaining)
        // or if items schema itself doesn't match.
        // The current `_validateList` logic for `items` applies it to all elements from `startIndex`.
        // So, `unevaluatedItems: false` would only trigger if `items` is null and `prefixItems` doesn't cover all.
        // Let's re-test with `items` present.
        final schemaWithItems = ListSchema(
          prefixItems: [IntegerSchema()],
          items: StringSchema(
            minLength: 2,
          ), // Applies to items after prefixItems
          unevaluatedItems: false, // Should not be hit if items covers the rest
        );
        // [10, "a"] -> "a" fails StringSchema(minLength:2), so itemInvalid
        expectFailures(
          schemaWithItems,
          [10, 'a'],
          [ValidationError.itemInvalid],
        );

        // If items is null, then unevaluatedItems:false applies to items after prefixItems
        final schemaNoItems = ListSchema(
          prefixItems: [IntegerSchema()],
          // items: null, (implicit)
          unevaluatedItems: false,
        );
        expectFailures(
          schemaNoItems,
          [10, 'extra string'],
          [ValidationError.unevaluatedItemNotAllowed],
        );
      });
    });

    group('String Specific', () {
      test('minLengthNotMet', () {
        final schema = StringSchema(minLength: 3);
        expectFailures(schema, 'hi', [ValidationError.minLengthNotMet]);
      });

      test('maxLengthExceeded', () {
        final schema = StringSchema(maxLength: 3);
        expectFailures(schema, 'hello', [ValidationError.maxLengthExceeded]);
      });

      test('patternMismatch', () {
        final schema = StringSchema(pattern: r'^\d+$');
        expectFailures(schema, 'abc', [ValidationError.patternMismatch]);
      });
    });

    group('Number Specific', () {
      test('minimumNotMet', () {
        final schema = NumberSchema(minimum: 10);
        expectFailures(schema, 5, [ValidationError.minimumNotMet]);
      });

      test('maximumExceeded', () {
        final schema = NumberSchema(maximum: 10);
        expectFailures(schema, 15, [ValidationError.maximumExceeded]);
      });

      test('exclusiveMinimumNotMet - equal value', () {
        final schema = NumberSchema(exclusiveMinimum: 10);
        expectFailures(schema, 10, [ValidationError.exclusiveMinimumNotMet]);
      });
      test('exclusiveMinimumNotMet - smaller value', () {
        final schema = NumberSchema(exclusiveMinimum: 10);
        expectFailures(schema, 9, [ValidationError.exclusiveMinimumNotMet]);
      });

      test('exclusiveMaximumExceeded - equal value', () {
        final schema = NumberSchema(exclusiveMaximum: 10);
        expectFailures(schema, 10, [ValidationError.exclusiveMaximumExceeded]);
      });
      test('exclusiveMaximumExceeded - larger value', () {
        final schema = NumberSchema(exclusiveMaximum: 10);
        expectFailures(schema, 11, [ValidationError.exclusiveMaximumExceeded]);
      });

      test('multipleOfInvalid', () {
        final schema = NumberSchema(multipleOf: 3);
        expectFailures(schema, 10, [ValidationError.multipleOfInvalid]);
      });
      test('multipleOfInvalid - floating point', () {
        final schema = NumberSchema(multipleOf: 0.1);
        expectFailures(schema, 0.25, [ValidationError.multipleOfInvalid]);
      });
      test('multipleOfInvalid - valid floating point', () {
        final schema = NumberSchema(multipleOf: 0.1);
        expectFailures(schema, 0.3, []);
      });
    });

    group('Integer Specific', () {
      test('minimumNotMet', () {
        final schema = IntegerSchema(minimum: 10);
        expectFailures(schema, 5, [ValidationError.minimumNotMet]);
      });

      test('maximumExceeded', () {
        final schema = IntegerSchema(maximum: 10);
        expectFailures(schema, 15, [ValidationError.maximumExceeded]);
      });

      test('exclusiveMinimumNotMet - equal value', () {
        final schema = IntegerSchema(exclusiveMinimum: 10);
        expectFailures(schema, 10, [ValidationError.exclusiveMinimumNotMet]);
      });
      test('exclusiveMinimumNotMet - smaller value', () {
        final schema = IntegerSchema(exclusiveMinimum: 10);
        expectFailures(schema, 9, [ValidationError.exclusiveMinimumNotMet]);
      });

      test('exclusiveMaximumExceeded - equal value', () {
        final schema = IntegerSchema(exclusiveMaximum: 10);
        expectFailures(schema, 10, [ValidationError.exclusiveMaximumExceeded]);
      });
      test('exclusiveMaximumExceeded - larger value', () {
        final schema = IntegerSchema(exclusiveMaximum: 10);
        expectFailures(schema, 11, [ValidationError.exclusiveMaximumExceeded]);
      });

      test('multipleOfInvalid', () {
        final schema = IntegerSchema(multipleOf: 3);
        expectFailures(schema, 10, [ValidationError.multipleOfInvalid]);
      });
    });

    group('Complex scenarios and interactions', () {
      test('allOf with type constraint on parent schema', () {
        // Schema is explicitly a string, and also has allOf constraints.
        // To achieve this, we construct the map directly.
        final schema = Schema.fromMap({
          'type': JsonType.string.typeName,
          'minLength': 2, // This is from the main schema's direct validation
          'allOf': [
            // This is from allOf
            StringSchema(maxLength: 5),
            StringSchema(pattern: r'^[a-z]+$'),
          ],
        });

        // Fails minLength (from parent StringSchema) and pattern (from allOf)
        expectFailures(schema, 'A', [
          ValidationError.minLengthNotMet, // From StringSchema validation part
          ValidationError.allOfNotMet, // allOf combinator failed
          ValidationError
              .patternMismatch, // Specific reason from allOf sub-schema
        ]);

        // Fails maxLength (from allOf)
        expectFailures(schema, 'abcdef', [
          ValidationError.allOfNotMet, // allOf combinator failed
          ValidationError
              .maxLengthExceeded, // Specific reason from allOf sub-schema
        ]);
      });

      test('Object with property value invalid (deeper failure)', () {
        final schema = ObjectSchema(
          properties: {
            'user': ObjectSchema(
              properties: {'name': StringSchema(minLength: 5)},
            ),
          },
        );
        // 'user.name' is "hi" which fails minLength: 5
        // _validate(StringSchema(minLength:5), "hi") -> [minLengthNotMet]
        // This becomes propertyValueInvalid for 'name'
        // Then this becomes propertyValueInvalid for 'user'
        expectFailures(
          schema,
          {
            'user': {'name': 'hi'},
          },
          [ValidationError.propertyValueInvalid],
        );
      });

      test('List with item invalid (deeper failure)', () {
        final schema = ListSchema(
          items: ObjectSchema(properties: {'id': IntegerSchema(minimum: 100)}),
        );
        // The object {'id': 10} fails IntegerSchema(minimum:100)
        // _validate(ObjectSchema(...), {'id':10}) -> [propertyValueInvalid] (due to id:10 failing)
        // So the list item is invalid.
        expectFailures(
          schema,
          [
            {'id': 101},
            {'id': 10}, // This item is invalid
          ],
          [ValidationError.itemInvalid],
        );
      });

      test('Object with additionalProperties schema', () {
        final schema = ObjectSchema(
          properties: {'known': StringSchema()},
          additionalProperties: IntegerSchema(minimum: 0),
        );
        // Valid: known property and valid additional property
        expectFailures(schema, {'known': 'yes', 'extraNum': 10}, []);
        // Invalid: additional property fails its schema
        expectFailures(
          schema,
          {'known': 'yes', 'extraNum': -5},
          [ValidationError.additionalPropertyNotAllowed],
        );
        // Invalid: additional property is wrong type for its schema
        expectFailures(
          schema,
          {'known': 'yes', 'extraStr': 'text'},
          [ValidationError.additionalPropertyNotAllowed],
        );
      });

      test('Object with unevaluatedProperties: false and patternProperties', () {
        final schema = ObjectSchema(
          patternProperties: {r'^x-': StringSchema()},
          unevaluatedProperties: false,
        );
        // Valid: matches patternProperty
        expectFailures(schema, {'x-foo': 'bar'}, []);
        // Invalid: does not match patternProperty, and unevaluatedProperties is false
        expectFailures(
          schema,
          {'y-foo': 'bar'},
          [ValidationError.unevaluatedPropertyNotAllowed],
        );
      });

      test(
        'Object with unevaluatedProperties: false, properties, and additionalProperties: true (should allow unevaluated)',
        () {
          final schema = ObjectSchema(
            properties: {'name': StringSchema()},
            additionalProperties: true, // Allows any additional properties
            unevaluatedProperties:
                false, // This should be superseded by additionalProperties: true for evaluation purposes
          );
          // 'age' is covered by additionalProperties: true, so it's evaluated (and allowed).
          // Thus, unevaluatedProperties: false should not trigger.
          expectFailures(schema, {'name': 'test', 'age': 30}, []);
        },
      );

      test(
        'Object with unevaluatedProperties: false, properties, and additionalProperties: Schema (valid additional)',
        () {
          final schema = ObjectSchema(
            properties: {'name': StringSchema()},
            additionalProperties: IntegerSchema(),
            unevaluatedProperties: false,
          );
          // 'age' is covered by additionalProperties: IntegerSchema, and 30 is a valid integer.
          // So it's evaluated. unevaluatedProperties: false should not trigger.
          expectFailures(schema, {'name': 'test', 'age': 30}, []);
        },
      );

      test(
        'Object with unevaluatedProperties: false, properties, and additionalProperties: Schema (invalid additional)',
        () {
          final schema = ObjectSchema(
            properties: {'name': StringSchema()},
            additionalProperties: IntegerSchema(minimum: 100),
            unevaluatedProperties: false,
          );
          // 'age' is covered by additionalProperties: IntegerSchema(minimum:100), but 30 is invalid.
          // This should result in `additionalPropertyNotAllowed`.
          // `unevaluatedProperties` should not trigger because 'age' was subject to evaluation by `additionalProperties`.
          expectFailures(
            schema,
            {'name': 'test', 'age': 30},
            [ValidationError.additionalPropertyNotAllowed],
          );
        },
      );

      test('List with unevaluatedItems: false and items schema', () {
        final schema = ListSchema(
          items: IntegerSchema(), // Applies to all items if no prefixItems
          unevaluatedItems: false,
        );
        // Valid: all items match IntegerSchema
        expectFailures(schema, [1, 2, 3], []);
        // Invalid: one item does not match IntegerSchema, results in itemInvalid
        // unevaluatedItems:false should not trigger because items schema applies.
        expectFailures(schema, [1, 'b', 3], [ValidationError.itemInvalid]);
      });

      test(
        'List with unevaluatedItems: false, prefixItems, and items schema',
        () {
          final schema = ListSchema(
            prefixItems: [StringSchema()],
            items: IntegerSchema(), // Applies to items after prefixItems
            unevaluatedItems: false,
          );
          // Valid
          expectFailures(schema, ['a', 1, 2], []);
          // Invalid: item after prefixItems fails IntegerSchema
          expectFailures(schema, ['a', 1, 'c'], [ValidationError.itemInvalid]);
          // Invalid: prefixItem fails StringSchema
          expectFailures(
            schema,
            [10, 1, 2],
            [ValidationError.prefixItemInvalid],
          );
        },
      );

      test(
        'Schema with no type but with type-specific constraints (e.g. minLength on a generic schema)',
        () {
          // This schema is malformed from a JSON Schema perspective,
          // as minLength only applies to strings.
          // The current validator will apply combinators first.
          // Then, if schema.type is null, it won't call _validateString, _validateNumber etc.
          // So, minLength would be ignored if not for a sub-schema in allOf/anyOf/oneOf/not.
          final schemaWithMinLengthNoType = Schema.fromMap({'minLength': 5});
          expectFailures(
            schemaWithMinLengthNoType,
            'hi',
            [],
          ); // minLength is ignored as type is not string
          expectFailures(
            schemaWithMinLengthNoType,
            12345,
            [],
          ); // minLength is ignored

          // If combined with a type via allOf:
          // The StringSchema() in allOf will make the effective type string.
          // Then _validateString will be called for the combined schema if its type is string.
          // The _validate function:
          // 1. Handles combinators. `_validate(Schema.fromMap({'minLength': 10}), "short")` is called.
          //    This inner _validate sees type=null, so minLength is ignored by it. It returns [].
          //    `_validate(StringSchema(), "short")` returns [].
          //    So allOf passes.
          // 2. Handles explicit type. If combinedSchema's `type` field is set to `string` (which it isn't by Schema.combined directly unless specified),
          //    then _validateString(combinedSchema, "short") would be called.
          //    The `StringSchema` factory sets `type: 'string'`.
          //    `Schema.combined` does not set a top-level type unless explicitly passed.

          // Let's test StringSchema(allOf: [Schema.fromMap({'pattern': '^[a-z]+$'})])
          // This is more like: StringSchema has minLength, and allOf has pattern.
          final s = Schema.fromMap({
            'type': JsonType.string.typeName,
            'minLength': 5,
            'allOf': [
              Schema.fromMap({'pattern': r'^[a-z]+$'}),
            ],
          });
          // "Hi" fails minLength.
          // For allOf: Schema.fromMap({'pattern': '^[a-z]+$'}).validate("Hi") -> pattern is ignored as type is null.
          // So the allOf sub-schema (which has no type) passes. The allOf combinator itself passes.
          // Then StringSchema part: minLength:5 fails "Hi".
          // Result: [minLengthNotMet]
          expectFailures(s, 'Hi', [ValidationError.minLengthNotMet]);

          // "Hiall" passes minLength.
          // allOf part passes.
          // Result: []
          expectFailures(s, 'Hiall', []);

          // To make the pattern apply, it needs to be a StringSchema too.
          final s2 = Schema.fromMap({
            'type': JsonType.string.typeName,
            'minLength': 5,
            'allOf': [StringSchema(pattern: r'^[a-z]+$')],
          });
          // "LongEnoughButCAPS"
          // minLength:5 passes.
          // allOf: StringSchema(pattern: '^[a-z]+$').validate("LongEnoughButCAPS") -> [patternMismatch]
          // So allOf fails.
          // Result: [allOfNotMet, patternMismatch]
          expectFailures(s2, 'LongEnoughButCAPS', [
            ValidationError.allOfNotMet,
            ValidationError.patternMismatch,
          ]);
        },
      );
    });
  });
}
