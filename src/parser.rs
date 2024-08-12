use crate::lexer::Token;

pub struct Parser{}

impl Parser{
    pub fn new() -> Self{
        Parser {}
    }

    /**
     * (For now) only prints the given tokens in one line and makes line breaks every 
     * time a line break occurs and inserts tabs whenever a tab occurs
     */
    pub fn parse_tokens(&self, tokens: Vec<Token>){
        let mut begin_of_line = true;
        for token in tokens {
            if !begin_of_line {
                print!("__")
            }
            begin_of_line = false;
            if token == Token::Indentation {
                print!("\t");
            }
            print!("{:?}", token);
            if token == Token::LineBreak {
                println!();
                begin_of_line = true;
            }
        }
        println!();
    }
}