package org.bu.jenkins.util;

import java.io.BufferedReader;
import java.io.StringReader;
import java.util.ArrayList;
import java.util.List;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

/**
 * Turn a multi-line string into a list, one list item per line in the string.
 * Provides a filter for implementation to omit/modify list items.
 * 
 * @author wrh
 *
 */
public abstract class StringToList {
	
	Logger logger = LogManager.getLogger(StringToList.class.getName());

	private String str;

	public StringToList(String str) {
		this.str = str;
	}
	
	public abstract String filter(String s);

	public List<String> getList() {
		List<String> items = new ArrayList<String>();
		if(str == null || str.isBlank()) {
			return items;
		}
		BufferedReader bf = new BufferedReader(new StringReader(str));
		String item = null;
		try {
			while((item = bf.readLine()) != null) {
				item = filter(item);
				if(item == null) {
					continue;
				}
				items.add(item);
			}
			return items;
		} 
		catch (Exception e) {
			logger.error(e.getMessage(), e);
			items.add(e.getMessage());
			return items;
		}

	}
}
