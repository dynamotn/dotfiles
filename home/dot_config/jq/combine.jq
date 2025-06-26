# Combine two entities in an array-oriented fashion.
# If uniq is true, then pass the results of the following through unique:
# if both are arrays:  a + b
# else if a is an array: a + [b]
# else if b is an array: [a] + b
# else [a, b]
def aggregate(a;b;uniq):
  if uniq then aggregate(a; b; false) | unique
  elif (a|type) == "array" then
    if (b|type) == "array" then a + b
    else a + [b]
    end
  else
    if (b|type) == "array" then [a] + b
    else [a, b]
    end
  end;

# Combine . with obj using aggregate/3 for shared keys whose values differ
def combine(obj):
  . as $in
  | reduce (obj|keys|.[]) as $key
      ($in;
       if .[$key] == obj[$key] then .
       else setpath([$key];
            aggregate( $in|getpath([$key]); obj|getpath([$key]); true ) )
       end ) ;

def demo:
    { "id": 123, "son": "Son1", "surname": "S"} as $row1
  | { "id": 123, "son": "Son2", "surname": "S"} as $row2
  |  $row1 | combine($row2 )
;
