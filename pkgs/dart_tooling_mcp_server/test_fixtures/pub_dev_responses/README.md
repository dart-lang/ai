To regenerate these responses run the relevant tests with RECREATE_GOLDEN_RESPONSES set:

```
> RECREATE_GOLDEN_RESPONSES=all \
  dart test/tools/pub_dev_search_test.dart
```

For regenerating a single response, delete the relevant file and run

```
> RECREATE_GOLDEN_RESPONSES=missing dart test/tools/pub_dev_search_test.dart
```