// ============================================================
//  JsonOut — a tiny ordered JSON writer.
//  Processing's JSONObject is backed by a HashMap, so it scrambles key
//  order. Jev reads the state as text, and "far_left … far_right" reads
//  far better in order, so the state is serialised with this instead.
//  Values may be String, Number, Boolean, JsonOut, or a List of those.
// ============================================================

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

class JsonOut {
  LinkedHashMap<String, Object> map = new LinkedHashMap<String, Object>();

  JsonOut put(String key, Object value) {
    map.put(key, value);
    return this;
  }

  String toJson() {
    StringBuilder sb = new StringBuilder();
    writeValue(sb, this);
    return sb.toString();
  }

  void writeValue(StringBuilder sb, Object v) {
    if (v == null) {
      sb.append("null");
    } else if (v instanceof JsonOut) {
      sb.append('{');
      boolean first = true;
      for (Map.Entry<String, Object> e : ((JsonOut) v).map.entrySet()) {
        if (!first) sb.append(',');
        first = false;
        writeString(sb, e.getKey());
        sb.append(':');
        writeValue(sb, e.getValue());
      }
      sb.append('}');
    } else if (v instanceof List) {
      sb.append('[');
      boolean first = true;
      for (Object item : (List) v) {
        if (!first) sb.append(',');
        first = false;
        writeValue(sb, item);
      }
      sb.append(']');
    } else if (v instanceof String) {
      writeString(sb, (String) v);
    } else if (v instanceof Number || v instanceof Boolean) {
      sb.append(v.toString());
    } else {
      writeString(sb, v.toString());
    }
  }

  void writeString(StringBuilder sb, String s) {
    sb.append('"');
    for (int i = 0; i < s.length(); i++) {
      char c = s.charAt(i);
      switch (c) {
        case '"':  sb.append("\\\""); break;
        case '\\': sb.append("\\\\"); break;
        case '\n': sb.append("\\n");  break;
        case '\r': sb.append("\\r");  break;
        case '\t': sb.append("\\t");  break;
        default:
          if (c < 0x20) sb.append(String.format("\\u%04x", (int) c));
          else sb.append(c);
      }
    }
    sb.append('"');
  }
}
