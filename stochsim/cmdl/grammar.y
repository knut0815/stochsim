// Configuration of output
%token_prefix TOKEN_
%start_symbol model
%parse_failure {throw std::exception("Syntax error.");}
%stack_overflow {throw std::exception("Parser stack overflow while parsing cmdl file.");}
%name internal_Parse
%token_type {terminal_symbol*}
%token_destructor {
	delete $$;
	$$ = nullptr;
}
%extra_argument {parse_tree* parseTree}

%include {#include "../expression/expression.h"}
%include {#include "../expression/comparison_expression.h"}
%include {#include "../expression/conditional_expression.h"}
%include {#include "../expression/exponentiation_expression.h"}
%include {#include "../expression/logical_expression.h"}
%include {#include "../expression/number_expression.h"}
%include {#include "../expression/product_expression.h"}
%include {#include "../expression/sum_expression.h"}
%include {#include "../expression/variable_expression.h"}
%include {#include "../expression/function_expression.h"}

%include {#include "symbols.h"}
%include {#include "parse_tree.h"}
%include {#include "parser.h"}

%include {#include  <assert.h>}
%include {using namespace expression;}
%include {using namespace cmdl;}
%include {#undef NDEBUG} // necessary for ParseTrace
// Convert c-style parsing functions to implementation of clean c++ class handling everything.
%include {
	// Forward declaration parser functions.
	void internal_Parse(
		void *yyp,                   /* The parser */
		int yymajor,                 /* The major token code number */
		terminal_symbol* yyminor,       /* The value for the token */
		parse_tree* parse_tree               /* Optional %extra_argument parameter */
	);

	void *internal_ParseAlloc(void* (*mallocProc)(size_t));

	void internal_ParseFree(
		void *p,                    /* The parser to be deleted */
		void(*freeProc)(void*)     /* Function used to reclaim memory */
	);
	void internal_ParseTrace(FILE *TraceFILE, char *zTracePrompt);
	void cmdl::parser::initialize_internal()
	{
		uninitialize_internal();
		if (logFilePath_.empty())
		{
			logFile_ = nullptr;
		}
		else
		{
			fopen_s(&logFile_, logFilePath_.c_str(), "w");
			if(logFile_)
				internal_ParseTrace(logFile_, "cmdl_");
			else
				internal_ParseTrace(0, "cmdl_");
		}
		try
		{
			handle_ = internal_ParseAlloc(malloc);
		}
		catch (...)
		{
			throw std::exception("Could not allocate space for cmdl parser.");
		}
		if (!handle_)
		{
			throw std::exception("Could not create cmdl parser.");
		}
	}
	void cmdl::parser::uninitialize_internal()
	{
		if(!handle_)
			return;
		internal_ParseTrace(0, "cmdl_");
		internal_ParseFree(handle_, free); 
		handle_ = nullptr;
		if (logFile_)
			fclose(logFile_);
		logFile_ = nullptr;
	}

	void cmdl::parser::parse_token(int tokenID, cmdl::terminal_symbol* token, cmdl::parse_tree& parseTree)
	{
		if (!handle_)
		{
			throw std::exception("Parser handle invalid.");
		}
		try
		{
			internal_Parse(handle_, tokenID, token, &parseTree);
		}
		catch (const std::exception& ex)
		{
			throw ex;
		}
		catch (...)
		{
			throw std::exception("Unknown error");
		}
	}
}


/////////////////////////////////////////////////////////////////////////////
// Define precedence
/////////////////////////////////////////////////////////////////////////////
/* Copied from the lemon documentation:
* The precedence of non-terminals is transferred to rules as follows: The precedence of a grammar rule is equal to the precedence of the left-most terminal symbol in the rule for which a precedence is defined. This is normally what you want, but in those cases where you want to precedence of a grammar rule to be something different, you can specify an alternative precedence symbol by putting the symbol in square braces after the period at the end of the rule and before any C-code. For example:
* 
*    expr = MINUS expr.  [NOT]
* 
* This rule has a precedence equal to that of the NOT symbol, not the MINUS symbol as would have been the case by default.
* 
* With the knowledge of how precedence is assigned to terminal symbols and individual grammar rules, we can now explain precisely how parsing conflicts are resolved in Lemon. 
* Shift-reduce conflicts are resolved as follows:
* 
*     If either the token to be shifted or the rule to be reduced lacks precedence information, then resolve in favor of the shift, but report a parsing conflict.
*     If the precedence of the token to be shifted is greater than the precedence of the rule to reduce, then resolve in favor of the shift. No parsing conflict is reported.
*     If the precedence of the token it be shifted is less than the precedence of the rule to reduce, then resolve in favor of the reduce action. No parsing conflict is reported.
*     If the precedences are the same and the shift token is right-associative, then resolve in favor of the shift. No parsing conflict is reported.
*     If the precedences are the same the the shift token is left-associative, then resolve in favor of the reduce. No parsing conflict is reported.
*     Otherwise, resolve the conflict by doing the shift and report the parsing conflict. 
* 
* Reduce-reduce conflicts are resolved this way:
* 
*     If either reduce rule lacks precedence information, then resolve in favor of the rule that appears first in the grammar and report a parsing conflict.
*     If both rules have precedence and the precedence is different then resolve the dispute in favor of the rule with the highest precedence and do not report a conflict.
*     Otherwise, resolve the conflict by reducing by the rule that appears first in the grammar and report a parsing conflict. 
*/

// A statement is finished with a semicolon only after all rules having a precedence higher than a semicolon are applied. Rules having the precedence of a semicolon are only
// applied if they have to, which is convenient for conversion rules which should only be applied if nothing else works.
%right SEMICOLON. 
%right QUESTIONMARK.
%left AND.
%left OR.
%nonassoc EQUAL NOT_EQUAL GREATER GREATER_EQUAL LESS LESS_EQUAL.
%left PLUS MINUS.
%left MULTIPLY DIVIDE.
%right EXP NOT.
%nonassoc IDENTIFIER VALUE. // always prefer longer rules


/////////////////////////////////////////////////////////////////////////////
// Rules
/////////////////////////////////////////////////////////////////////////////
// A model consists of a set of statements.
model ::= statements.
statements ::= statements statement.
statements ::= .

// A statement can either be a variable assignment or a reaction
statement ::= assignment.
statement ::= reaction.
statement ::= error. // we have to define a symbol of type error somewhere to trigger the error handling routines

// Basic mathematical expressions
%type expression {expression_base*}
%destructor expression { 
	delete $$;
	$$ = nullptr;
}
expression(e) ::= IDENTIFIER(I). [SEMICOLON] {
	e = new variable_expression(*I);
	delete I;
	I = nullptr;
}
expression(e) ::= IDENTIFIER(I) LEFT_ROUND arguments(as) RIGHT_ROUND . [SEMICOLON] {
	auto func = new function_expression(*I);
	delete I;
	I = nullptr;
	e = nullptr;
	for(auto& argument : *as)
	{
		func->push_back(std::move(argument));
	}
	delete as;
	as = nullptr;
	e = func;
	func = nullptr;
}

expression(e) ::= VALUE(V). [SEMICOLON]{
	e = new number_expression(*V);
	delete V;
	V = nullptr;
}
expression(e_new) ::= LEFT_ROUND expression(e_old) RIGHT_ROUND. {
	e_new = e_old;
} // forces sums, ..., to be converted to an expression.

%type comparison {conditional_expression*}
%destructor comparison { 
	delete $$;
	$$ = nullptr;
}
comparison(e) ::= expression(c) QUESTIONMARK expression(e1) COLON expression(e2). [QUESTIONMARK]{
	e = new conditional_expression(std::unique_ptr<expression_base>(c), std::unique_ptr<expression_base>(e1), std::unique_ptr<expression_base>(e2));
	e1 = nullptr;
	e2 = nullptr;
	c = nullptr;
}
expression(e) ::= comparison(s). [EXP] {
	e = s;
}

// Arguments
%type arguments {arguments*}
%destructor arguments { 
	delete $$;
	$$ = nullptr;
}
arguments(as) ::= . [SEMICOLON] {
	as = new arguments();
}
arguments(as) ::= expression(e). [COMMA]{
	as = new arguments();
	as->push_back(typename arguments::value_type(e));
	e = nullptr;
}
arguments(as_new) ::= arguments(as_old) COMMA expression(e). [COMMA]{
	as_new = as_old;
	as_old = nullptr;
	as_new->push_back(typename arguments::value_type(e));
	e = nullptr;
}

// Sum
%type sum {sum_expression*}
%destructor sum { 
	delete $$;
	$$ = nullptr;
}
expression(e) ::= sum(s). [PLUS] {
	e = s;
}
sum(s) ::= expression(e1) PLUS expression(e2). {
	s = new sum_expression();
	s->push_back(false, std::unique_ptr<expression_base>(e1));
	s->push_back(false, std::unique_ptr<expression_base>(e2));
}
sum(s) ::= expression(e1) MINUS expression(e2). {
	s = new sum_expression();
	s->push_back(false,  std::unique_ptr<expression_base>(e1));
	s->push_back(true, std::unique_ptr<expression_base>(e2));
}
sum(s_new) ::= sum(s_old) PLUS expression(e). {
	s_new = s_old;
	s_new->push_back(false, std::unique_ptr<expression_base>(e));
}
sum(s_new) ::= sum(s_old) MINUS expression(e). {
	s_new = s_old;
	s_new->push_back(true, std::unique_ptr<expression_base>(e));
}


// Product
%type product {product_expression*}
%destructor product { 
	delete $$;
	$$ = nullptr;
}
expression(e) ::= product(p). [MULTIPLY] {
	e = p;
}
product(p) ::= expression(e1) MULTIPLY expression(e2). {
	p = new product_expression();
	p->push_back(false, std::unique_ptr<expression_base>(e1));
	p->push_back(false, std::unique_ptr<expression_base>(e2));

}
product(p) ::= expression(e1) DIVIDE expression(e2). {
	p = new product_expression();
	p->push_back(false, std::unique_ptr<expression_base>(e1));
	p->push_back(true, std::unique_ptr<expression_base>(e2));

}
product(p_new) ::= product(p_old) MULTIPLY expression(e). {
	p_new = p_old;
	p_new->push_back(false, std::unique_ptr<expression_base>(e));
}
product(p_new) ::= product(p_old) DIVIDE expression(e). {
	p_new = p_old;
	p_new->push_back(true, std::unique_ptr<expression_base>(e));
}

// conjunction
%type conjunction {conjunction_expression*}
%destructor conjunction { 
	delete $$;
	$$ = nullptr;
}
expression(e) ::= conjunction(c). [AND] {
	e = c;
}
conjunction(c) ::= expression(e1) AND expression(e2). {
	c = new conjunction_expression();
	c->push_back(false, std::unique_ptr<expression_base>(e1));
	c->push_back(false, std::unique_ptr<expression_base>(e2));

}
conjunction(c_new) ::= conjunction(c_old) AND expression(e). {
	c_new = c_old;
	c_new->push_back(false, std::unique_ptr<expression_base>(e));
}

// disjunction
%type disjunction {disjunction_expression*}
%destructor disjunction { 
	delete $$;
	$$ = nullptr;
}
expression(e) ::= disjunction(c). [OR] {
	e = c;
}
disjunction(c) ::= expression(e1) OR expression(e2). {
	c = new disjunction_expression();
	c->push_back(false, std::unique_ptr<expression_base>(e1));
	c->push_back(false, std::unique_ptr<expression_base>(e2));

}
disjunction(c_new) ::= disjunction(c_old) OR expression(e). {
	c_new = c_old;
	c_new->push_back(false, std::unique_ptr<expression_base>(e));
}

// not
expression(e_new) ::= NOT expression(e_old). {
	e_new = new unary_not_expression(std::unique_ptr<expression_base>(e_old));
}

// unary minus
expression(e_new) ::= MINUS expression(e_old). [NOT] {
	e_new = new unary_minus_expression(std::unique_ptr<expression_base>(e_old));
}

// Exponentiation
expression(e_new) ::= expression(e1) EXP expression(e2). {
	e_new = new exponentiation_expression(std::unique_ptr<expression_base>(e1), std::unique_ptr<expression_base>(e2));
}


// Comparison
expression(e_new) ::= expression(e1) EQUAL expression(e2). {
	e_new = new comparison_expression(std::unique_ptr<expression_base>(e1), std::unique_ptr<expression_base>(e2), comparison_expression::type_equal);
}
expression(e_new) ::= expression(e1) NOT_EQUAL expression(e2). {
	e_new = new comparison_expression(std::unique_ptr<expression_base>(e1), std::unique_ptr<expression_base>(e2), comparison_expression::type_not_equal);
}
expression(e_new) ::= expression(e1) GREATER expression(e2). {
	e_new = new comparison_expression(std::unique_ptr<expression_base>(e1), std::unique_ptr<expression_base>(e2), comparison_expression::type_greater);
}
expression(e_new) ::= expression(e1) GREATER_EQUAL expression(e2). {
	e_new = new comparison_expression(std::unique_ptr<expression_base>(e1), std::unique_ptr<expression_base>(e2), comparison_expression::type_greater_equal);
}
expression(e_new) ::= expression(e1) LESS expression(e2). {
	e_new = new comparison_expression(std::unique_ptr<expression_base>(e1), std::unique_ptr<expression_base>(e2), comparison_expression::type_less);
}
expression(e_new) ::= expression(e1) LESS_EQUAL expression(e2). {
	e_new = new comparison_expression(std::unique_ptr<expression_base>(e1), std::unique_ptr<expression_base>(e2), comparison_expression::type_less_equal);
}

// assignments
assignment ::= IDENTIFIER(I) ASSIGN expression(e) SEMICOLON. {
	// create_variable might throw an exception, which results in automatic destruction of I and e by the parser. We thus have to make sure that
	// they point to null to avoid double deletion.
	identifier name = *I;
	delete I;
	I = nullptr;
	auto e_temp = std::unique_ptr<expression_base>(e);
	e = nullptr;

	parseTree->create_variable(std::move(name), parseTree->get_expression_value(e_temp.get()));
}

assignment ::= IDENTIFIER(I) ASSIGN LEFT_SQUARE expression(e) RIGHT_SQUARE SEMICOLON. {
	// create_variable might throw an exception, which results in automatic destruction of I and e by the parser. We thus have to make sure that
	// they point to null to avoid double deletion.
	identifier name = *I;
	delete I;
	I = nullptr;
	auto e_temp = std::unique_ptr<expression_base>(e);
	e = nullptr;

	parseTree->create_variable(std::move(name), std::move(e_temp));
}


// reaction
reaction ::= reactionSide(reactants) ARROW reactionSide(products) COMMA reactionSpecifiers(rss) SEMICOLON. {
	// create_reaction might throw an exception, which results in automatic destruction of reactants, products and e by the parser. We thus have to make sure that
	// they point to null to avoid double deletion.
	auto reactants_temp = std::unique_ptr<reaction_side>(reactants);
	auto products_temp = std::unique_ptr<reaction_side>(products);
	auto rss_temp = std::unique_ptr<reaction_specifiers>(rss);
	rss = nullptr;
	reactants = nullptr;
	products = nullptr;

	parseTree->create_reaction(std::move(reactants_temp), std::move(products_temp), std::move(rss_temp));
}

/*reaction ::= reactionSide(reactants) ARROW reactionSide(products) COMMA expression(e) SEMICOLON. {
	// create_reaction might throw an exception, which results in automatic destruction of reactants, products and e by the parser. We thus have to make sure that
	// they point to null to avoid double deletion.
	auto reactants_temp = std::unique_ptr<reaction_side>(reactants);
	auto products_temp = std::unique_ptr<reaction_side>(products);
	auto e_temp = e;
	reactants = nullptr;
	products = nullptr;
	e = nullptr;

	parseTree->create_reaction(std::move(reactants_temp), std::move(products_temp), parseTree->get_expression_value(e_temp));
	delete e_temp;
	e_temp = nullptr;
}
reaction ::= reactionSide(reactants) ARROW reactionSide(products) COMMA LEFT_SQUARE expression(e) RIGHT_SQUARE SEMICOLON. {
	// create_reaction might throw an exception, which results in automatic destruction of reactants, products and e by the parser. We thus have to make sure that
	// they point to null to avoid double deletion.
	auto reactants_temp = std::unique_ptr<reaction_side>(reactants);
	auto products_temp = std::unique_ptr<reaction_side>(products);
	auto e_temp = e;
	reactants = nullptr;
	products = nullptr;
	e = nullptr;

	parseTree->create_reaction(std::move(reactants_temp), std::move(products_temp), std::unique_ptr<expression_base>(e_temp));
}*/

%type reactionSpecifiers {reaction_specifiers*}
%destructor reactionSpecifiers { 
	delete $$;
	$$ = nullptr;
}
reactionSpecifiers(rss) ::= reactionSpecifier(rs) . {
	auto rss_temp = std::make_unique<reaction_specifiers>();
	auto rs_temp = std::unique_ptr<reaction_specifier>(rs);
	rs = nullptr;
	rss = nullptr;
	rss_temp->push_back(std::move(rs_temp));
	rss = rss_temp.release();
}
reactionSpecifiers(rss_new) ::= reactionSpecifiers(rss_old) COMMA reactionSpecifier(rs) . {
	auto rss_temp = std::unique_ptr<reaction_specifiers>(rss_old);
	rss_old = nullptr;
	rss_new = nullptr;
	auto rs_temp = std::unique_ptr<reaction_specifier>(rs);
	rs = nullptr;
	rss_temp->push_back(std::move(rs_temp));
	rss_new = rss_temp.release();
}

%type reactionSpecifier {reaction_specifier*}
%destructor reactionSpecifier { 
	delete $$;
	$$ = nullptr;
}
reactionSpecifier(rs) ::= expression(e). {
	auto e_temp = std::unique_ptr<expression_base>(e);
	e = nullptr;
	rs = nullptr;
	auto value = parseTree->get_expression_value(e_temp.get());
	rs = new reaction_specifier(reaction_specifier::rate_type, std::make_unique<number_expression>(value));
}

reactionSpecifier(rs) ::= IDENTIFIER(I) COLON expression(e). {
	auto e_temp = std::unique_ptr<expression_base>(e);
	e = nullptr;
	rs = nullptr;
	identifier name = *I;
	delete I;
	I = nullptr;
	auto value = parseTree->get_expression_value(e_temp.get());
	rs = new reaction_specifier(name, std::make_unique<number_expression>(value));
}

reactionSpecifier(rs) ::= LEFT_SQUARE expression(e) RIGHT_SQUARE. {
	auto e_temp = std::unique_ptr<expression_base>(e);
	e = nullptr;
	rs = nullptr;
	rs = new reaction_specifier(reaction_specifier::rate_type, std::move(e_temp));
}

%type reactionSide {reaction_side*}
%destructor reactionSide { 
	delete $$;
	$$ = nullptr;
}
reactionSide(rs) ::= . [SEMICOLON] {
	rs = new reaction_side();
}
reactionSide(rs) ::= reactionComponent(rc). [MULTIPLY]{
	auto rc_temp = std::unique_ptr<reaction_component>(rc);
	rc = nullptr;

	rs = new reaction_side();
	rs->push_back(std::move(rc_temp));
}
reactionSide(rs_new) ::= reactionSide(rs_old) PLUS reactionComponent(rc). [MULTIPLY]{
	rs_new = rs_old;
	rs_old = nullptr;
	auto rc_temp = std::unique_ptr<reaction_component>(rc);
	rc = nullptr;

	rs_new->push_back(std::move(rc_temp));
}

reactionSide ::= expression(e1) PLUS expression(e2). [MULTIPLY] {
	delete(e1);
	e1=nullptr;
	delete(e2);
	e2=nullptr;
	throw std::exception("Reactants or products of a reaction must either be state names, or an expression (representing the stochiometry of the state) times the state name, in this order.");
}



reactionSide ::= reactionSide(rs_old) PLUS expression(e). [PLUS] {
	delete(e);
	e=nullptr;
	delete(rs_old);
	rs_old=nullptr;
	throw std::exception("Reactants or products of a reaction must either be state names, or an expression (representing the stochiometry of the state) times the state name, in this order.");
}

%type reactionComponent {reaction_component*}
%destructor reactionComponent { 
	delete $$;
	$$ = nullptr;
}
reactionComponent(rc) ::= IDENTIFIER(I). [EXP]{
	identifier state = *I;
	delete I;
	I = nullptr;
	rc = nullptr;

	rc = new reaction_component(state, 1, false);
}

reactionComponent(rc) ::= IDENTIFIER(I) LEFT_SQUARE RIGHT_SQUARE. [EXP]{
	identifier state = *I;
	delete I;
	I = nullptr;
	rc = nullptr;

	rc = new reaction_component(state, 1, true);
}

reactionComponent(rc) ::= expression(e) MULTIPLY IDENTIFIER(I). [EXP]{
	identifier state = *I;
	delete I;
	I = nullptr;
	auto e_temp = std::unique_ptr<expression_base>(e);
	e = nullptr;
	rc = nullptr;

	auto stochiometry = parseTree->get_expression_value(e_temp.get());
	rc = new reaction_component(state, stochiometry, false);
}

reactionComponent(rc) ::= expression(e) MULTIPLY IDENTIFIER(I) LEFT_SQUARE RIGHT_SQUARE. [EXP]{
	identifier state = *I;
	delete I;
	I = nullptr;
	auto e_temp = std::unique_ptr<expression_base>(e);
	e = nullptr;
	rc = nullptr;

	auto stochiometry = parseTree->get_expression_value(e_temp.get());
	rc = new reaction_component(state, stochiometry, true);
}

reactionComponent(rc) ::= LEFT_SQUARE expression(e) QUESTIONMARK reactionSide(s1) COLON reactionSide(s2) RIGHT_SQUARE . [EXP]{
	auto e_temp = std::unique_ptr<expression_base>(e);
	e = nullptr;
	auto s1_temp = std::unique_ptr<reaction_side>(s1);
	auto s2_temp = std::unique_ptr<reaction_side>(s2);
	s1 = nullptr;
	s2 = nullptr;
	rc = nullptr;

	identifier state = parseTree->create_choice(std::move(e_temp), std::move(s1_temp), std::move(s2_temp));
	rc = new reaction_component(state, 1, false);
}
