// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Dart test program const map literals.

class ListLiteral2NegativeTest<T> {
  test() {
    // Type parameter is not allowed with const.
    var m = const <T>[0, 1];
    //      ^
    // [cfe] Constant evaluation error:
    //             ^
    // [analyzer] COMPILE_TIME_ERROR.INVALID_TYPE_ARGUMENT_IN_CONST_LIST
    // [cfe] Type variables can't be used as constants.
    //                ^
    // [analyzer] STATIC_WARNING.LIST_ELEMENT_TYPE_NOT_ASSIGNABLE
    //                   ^
    // [analyzer] STATIC_WARNING.LIST_ELEMENT_TYPE_NOT_ASSIGNABLE
  }
}

main() {
  ListLiteral2NegativeTest<int>().test();
}
