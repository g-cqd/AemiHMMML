// OpenJDK's java.util.Properties as an oracle for AemiConfigLines' JavaProperties (Tools/ConfigLinesAdapter, ADR-0023). Run as a
// single-file program: `java PropertiesOracle.java`. Input: records of a decimal length, a line feed and that many bytes. Output,
// for each: `OK n` then n lines `HEXKEY HEXVALUE` (UTF-8, keys sorted), or `ERR reason`. Bytes that are not UTF-8 are an error,
// as is a key or value holding a surrogate without its pair: text can hold neither.
import java.io.*;
import java.nio.ByteBuffer;
import java.nio.charset.*;
import java.util.*;

public class PropertiesOracle {
    public static void main(String[] arguments) throws IOException {
        DataInputStream in = new DataInputStream(new BufferedInputStream(System.in));
        PrintStream out = new PrintStream(new BufferedOutputStream(System.out), false, "UTF-8");
        while (true) {
            StringBuilder length = new StringBuilder();
            int c;
            while ((c = in.read()) != -1 && c != '\n') length.append((char) c);
            if (c == -1) break;
            byte[] bytes = new byte[Integer.parseInt(length.toString())];
            in.readFully(bytes);
            out.print(answer(bytes));
            out.flush();
        }
    }

    static String answer(byte[] bytes) {
        String text;
        try {
            text = StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString();
        } catch (CharacterCodingException error) {
            return "ERR utf8\n";
        }
        Properties properties = new Properties();
        try {
            properties.load(new StringReader(text));
        } catch (IllegalArgumentException error) {
            return "ERR malformed\n";
        } catch (IOException error) {
            return "ERR io\n";
        }
        TreeMap<String, String> sorted = new TreeMap<>();
        for (String key : properties.stringPropertyNames()) {
            String value = properties.getProperty(key);
            if (lone(key) || lone(value)) return "ERR surrogate\n";
            sorted.put(key, value);
        }
        StringBuilder result = new StringBuilder("OK " + sorted.size() + "\n");
        for (Map.Entry<String, String> entry : sorted.entrySet()) {
            result.append(hex(entry.getKey())).append(' ').append(hex(entry.getValue())).append('\n');
        }
        return result.toString();
    }

    static boolean lone(String text) {
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (Character.isHighSurrogate(c)) {
                if (i + 1 >= text.length() || !Character.isLowSurrogate(text.charAt(i + 1))) return true;
                i++;
            } else if (Character.isLowSurrogate(c)) {
                return true;
            }
        }
        return false;
    }

    static String hex(String text) {
        StringBuilder result = new StringBuilder("_");
        for (byte b : text.getBytes(StandardCharsets.UTF_8)) result.append(String.format("%02x", b & 0xff));
        return result.toString();
    }
}
