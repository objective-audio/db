# db
sqliteデータベースのラッパーです。

## db::model
データベースモデルの定義。Dictionaryで記述された構造を元に生成する。

```cpp
// モデルの生成

auto model_dict = make_objc_ptr<NSDictionary *>([]() {
    return @{
        @"entities": @{
            @"entity_a": @{
                @"attributes": @{
                    @"age": @{@"type": @"INTEGER", @"default": @1},
                    @"name": @{@"type": @"TEXT", @"default": @"empty_name"}
                }
            }
        },
        @"version": @"1.0.0"
    };
});

db::model model{(__bridge CFDictionaryRef)model_dict.object()};
```

|関数名|説明|
|:-|:-|
|version|モデルのバージョン。モデルの構造を変更した時は値を上げる必要がある。バージョンを上げるとdb::managerのセットアップ時に自動でテーブルの更新・追加が行われる。|
|entities|エンティティ定義の配列。要素の詳細は`entity`の項目を参照。|
|indices|インデックス定義の配列。要素の詳細は`index`の項目を参照。|
|entity|エンティティ名を指定して`db::entity`を取得|
|attributes|エンティティ名を指定して属性の定義の辞書を取得|
|relations|エンティティ名を指定して関連の定義の辞書を取得|
|attribute|エンティティと属性名を指定して属性の定義を取得|
|relation|エンティティと関連名を指定して関連の定義を取得|
|index|インデックス名を指定してインデックス定義を取得|

## db::entity
データベースオブジェクトの定義。`db::object`を扱う元となる情報。

|メンバ変数|説明|
|:-|:-|
|attributes|属性情報の辞書。Keyは属性の名前。要素の詳細は`attribute`の項目を参照|
|relations|関連情報の辞書。Keyは関連の名前。要素の詳細は`relation`の項目を参照|

## db::attribute
オブジェクトの属性の定義。`db::object`で`db::value`を扱う元となる情報。

|メンバ変数|型|説明|
|:-|:-|:-|
|name|std::string|名前|
|type|std::string|データ型。`INTEGER`・`TEXT`・`REAL`・`BLOB`のいずれか|
|not_null|bool|カラム生成時に`NOT NULL`を定義。`NULL`を格納できなくする|
|default_value|db::value|カラム生成時に`DEFAULT`で定義するデフォルト値|
|primary|bool|カラム生成時に`PRIMARY KEY AUTOINCREMENT`を定義|
|unique|bool|カラム生成時に`UNIQUE`を定義。他のデータと被らない値しか格納できなくする|

## db::relation
関連の定義

|メンバ変数|型|説明|補足|
|:-|:-|:-|:-|
|entity_name|std::string|関連元のエンティティ名||
|name|std::string|関連の名前||
|target_entity_name|std::string|関連先のエンティティ名||
|many|bool|対多か||
|table_name|std::string|関連のテーブル名|`entity_name`と`name`から自動で生成される|

## db::value
データベース用の値を保持するオブジェクト。immutableで値の変更はできない。

```cpp
db::value value{db::integer::type(1)};
    
value.type(); // -> typeid(db::integer) 
value.get<db::integer>(); // -> 1
```

メンバ関数`get`では以下のいずれかをテンプレートパラメータで指定して、実際の型で値を取得する。

|テンプレートパラメータ|実際の型|説明|
|:-|:-|:-|
|db::integer|sqlite3_int64|整数|
|db::real|double|浮動小数点数|
|db::text|std::string|文字列|
|db::blob|db::blob|バイトデータ。blobオブジェクト内にdataを持つ|

`db::value`の値が`NULL`の場合は、`operator bool()`で`false`を返す。

## db::const_object
データベース用のオブジェクト。値の変更はできない。

`db::entity`の情報を元に`db::manager`によって生成される。直接オブジェクトを生成することはしない。

|関数名|返り値|説明|
|:-|:-|:-|
|model|db::model|モデル|
|entity_name|std::string|エンティティ名|
|get_attribute|db::value|属性の値を取得|
|get_relation_ids|db::value_vector|関連先のIDの配列を取得|
|get_relation_id|db::value|idxの位置の関連先のIDを取得|
|relaiton_size|std::size_t|関連の数|
|object_id|db::value|オブジェクト固有のID|
|save_id|db::value|セーブID（保存されたタイミングごとにインクリメントされるID）|
|action|db::value|データベース上の編集状態。`insert`・`update`・`remove`のいずれか|

## db::object
データベース用のオブジェクト。`db::const_object`を継承し、値の変更ができるようにしたもの。

### Getter

|関数名|返り値|説明|
|:-|:-|:-|
|subject|subject_t|オブジェクトの変更を通知するオブジェクト|
|get_relation_objects|db::object_vector_t|関連先のオブジェクトの配列を取得|
|get_relation_object|db::object|idxの位置の関連先のオブジェクトを取得|
|manager|db::manager|オブジェクトの属するマネージャ|
|status|db::object_status|オブジェクトの状態。詳細は`object_status`の項目を参照|
|is_removed|bool|オブジェクトが削除されているか|

### Setter

|関数名|引数|説明|
|:-|:-|:-|
|set_attribute|std::string attr_name, db::value value|属性の値をセット|
|set_relation_ids|std::string rel_name, db::value_vector_t relation_ids|関連先のIDの配列をセット|
|push_back_relation_id|std::string rel_name, db::value relation_id|関連先のIDを配列の最後に追加|
|erase_relation_id|std::string rel_name, db::value relation_id|指定した関連先のIDを削除|
|set_relation_objects|std::string rel_name, db::object_vector_t rel_objects|関連先のオブジェクトの配列をセット|
|push_back_relation_object|std::string rel_name, db::object rel_object|関連先のオブジェクトを配列の最後に追加|
|erase_relation_object|std::string rel_name, db::object rel_object|関連先のオブジェクトを関連から外す|
|erase_relation|std::string rel_name, std::size_t idx|idxの位置の関連先のIDを削除|
|clear_relation|std::string rel_name|関連先のIDの配列を削除|
|remove|void|オブジェクトをデータベースから削除|

## db::object_status
`db::object`のマネージャー上での状態を表す。enumで定義されている。

|要素名|状態|
|:-|:-|
|invalid|マネージャに管理されていない状態|
|inserted|マネージャに挿入されてデータベースに保存されていない状態|
|saved|データベースに保存された状態|
|changed|データベースに保存されていてマネージャ上で変更された状態|
|updating|データベースに保存中の状態|

## db::manager



## cf_utils
## object_utils
## sql_utils
## utils
