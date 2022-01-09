package org.bu.jenkins.mvc.model;

import java.util.Arrays;
import java.util.Comparator;
import java.util.Set;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

/**
 * There are 5 basic landscapes (environments) that have traditionally been used for kuali deployments.
 * Therefore, they are enumerated here.
 * @author wrh
 *
 */
public enum Landscape {

	SANDBOX(1, "sb", "Sandbox environment", new String[] {"sandbox"}, "(?<![a-zA-Z])((sb)|(sandbox))(?![a-zA-Z]+)"),
	CI(2, "ci", "Continuous integration environment", new String[] {}, "(?<![a-zA-Z])(ci)(?![a-zA-Z]+)"),
	QA(3, "qa", "Quality assurance environment", new String[] {}, "(?<![a-zA-Z])(qa)(?![a-zA-Z]+)"),
	STAGING(4, "stg", "Staging environment", new String[] {"staging", "stage"}, "(?<![a-zA-Z])((stg)|(stage)|(staging))(?![a-zA-Z]+)"),
	PRODUCTION(5, "prod", "Production environment", new String[] {"production"}, "(?<![a-zA-Z])((prod)|(production))(?![a-zA-Z]+)");
	
	private Logger logger = LogManager.getLogger(Landscape.class.getName());
	
	private String id;
	private String description;
	private int order;
	private String[] aliases;
	private String regex;

	private Landscape(int order, String id, String description, String[] aliases, String regex) {
		this.order = order;
		this.id = id;
		this.description = description;
		this.aliases = aliases;
		this.regex = regex;
	}
	
	public static Set<Landscape> getIds() {
		Set<Landscape> ids = new TreeSet<Landscape>(new Comparator<Landscape>() {
			@Override public int compare(Landscape o1, Landscape o2) {
				return o1.getOrder() - o2.getOrder();
			}});
		ids.addAll(Arrays.asList(Landscape.values()));
		
		return ids;
	}
	
	/**
	 * If provided landscape name matches (excluding case) the id of a Landscape enum value or one of its aliases, then return the landscape id.
	 * Otherwise return the provided landscape unchanged.
	 * This will correct certain anticipated guesses at some of the standard landscape names, and enforce lowercasing.
	 * @param possibleAlias
	 * @return
	 */
	public static String idFromAlias(String possibleAlias) {
		if(possibleAlias == null || possibleAlias.isBlank()) {
			return possibleAlias;
		}
		Landscape landscape = fromAlias(possibleAlias);
		if(landscape == null) {
			return possibleAlias;
		}
		return landscape.getId();
	}
	
	public static Landscape fromAlias(String possibleAlias) {
		if(possibleAlias == null || possibleAlias.isBlank()) {
			return null;
		}
		for(Landscape landscape : Landscape.values()) {
			if(landscape.name().equalsIgnoreCase(possibleAlias)) {
				return landscape;
			}
			if(landscape.getId().equalsIgnoreCase(possibleAlias)) {
				return landscape;
			}
			else {
				for(String alias : landscape.getAliases()) {
					if(alias.equalsIgnoreCase(possibleAlias)) {
						return landscape;
					}
				}
			}
		}
		return null;		
	}
	
	public static boolean isBaseline(String landscape) {
		return idFromAlias(landscape) != null;
	}
	
	public boolean recognizedIn(String s) {
		Pattern p = Pattern.compile(regex);
		Matcher m = p.matcher(s.toLowerCase());
		if(m.find()) {
			if(m.groupCount() > 0) {
				return true;
			}
		}
		return false;
	}
	
	public static Landscape baselineRecognizedInString(String s) {
		Landscape match = null;
		for(Landscape baseline : Landscape.values()) {
			if(baseline.recognizedIn(s)) {
				if(match == null) {
					match = baseline;
				}
				else if(match.equals(baseline)) {
					// There's more than one matching baseline and they are not the same, so not really a match
					return null;
				}
			}
		}
		return match;
	}
	
	public boolean is(String landscape) {
		if(id.equalsIgnoreCase(landscape))
			return true;
		if(this.name().equalsIgnoreCase(landscape))
			return true;
		for(String alias : getAliases()) {
			if(alias.equalsIgnoreCase(landscape)) {
				return true;
			}
		}
		return false;
	}

	public String getId() {
		return id;
	}
	public int getOrder() {
		return order;
	}
	public String getDescription() {
		return description;
	}
	public String[] getAliases() {
		return aliases;
	}
	public String getRegex() {
		return regex;
	}
	
	public static void main(String[] args) {
		String[] matchable = new String[] {
				"SomeString-CI-thatShouldMatch",
				"SomeString-CI2-thatShouldMatch",
				"SomeString-2CI-thatShouldMatch",
				"CI_SomeStringThatShouldMatch",
				"SomeStringThatShouldMatch-CI",
				"SomeStringThatMightMatch-CI2",
				"CI2_SomeStringThatMightMatch"
			};
		String[] unmatchable = new String[] {
				"bogus",
				"SomeStringCIwithoutAnySeparators",
				"SomeString-CIwithoutTrailingSeparator",
				"SomeStringCI-withoutLeadingSeparator",
				"CISomeStringThatShouldNotMatch",
				"SomeStringThatShouldNotMatchCI",
			};
		boolean failure = false;
		for(String sample : matchable) {
			if(! CI.recognizedIn(sample)) {
				System.out.println("CI NOT recognized in " + sample + " when it should be");
				failure = true;
			}
		}
		for(String sample : unmatchable) {
			if(CI.recognizedIn(sample)) {
				System.out.println("CI recognized in " + sample + " when it should NOT be");
				failure = true;
			}
		}
		if( ! failure) {
			System.out.println("All tests passed!");
		}
	}
}