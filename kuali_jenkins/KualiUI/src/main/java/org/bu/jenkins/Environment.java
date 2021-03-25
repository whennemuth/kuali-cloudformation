package org.bu.jenkins;

public interface Environment {

	boolean containsKey(String key);

	String get(String key);

}
